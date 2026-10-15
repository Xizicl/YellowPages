import os
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from pathlib import Path
import uvicorn

from app.database import init_db
from app.routes import sync, numbers, reports, admin, appeals
from app.schemas import APIResponse

@asynccontextmanager
async def lifespan(app: FastAPI):
    # 启动时初始化数据库与种子数据
    await init_db()
    yield

app = FastAPI(
    title="YellowPages Backend Service",
    description="高并发、轻量级、完全对齐 CallKit 单一事实源规范的黄页号码反查与同步后端服务",
    version="1.0.0",
    lifespan=lifespan,
)

# 配置 CORS 中间件（适配 iOS 本机与 Web 控制台跨域请求）
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 挂载业务路由
app.include_router(sync.router)
app.include_router(numbers.router)
app.include_router(reports.router)
app.include_router(appeals.router)
app.include_router(admin.router)

@app.get("/health", response_model=APIResponse[dict], tags=["系统健康监控"])
async def health_check():
    """健康检查接口"""
    return APIResponse.ok(data={"status": "healthy", "service": "yellowpages-backend"})

# 静态资源与前端单页应用 (SPA) 托管
STATIC_DIR = Path(__file__).resolve().parent / "static"
if STATIC_DIR.exists():
    app.mount("/assets", StaticFiles(directory=STATIC_DIR / "assets"), name="assets")
    
    from fastapi.responses import FileResponse
    @app.get("/", tags=["管理控制台入口"])
    async def index_page():
        index_file = STATIC_DIR / "index.html"
        if index_file.exists():
            return FileResponse(index_file)
        return {
            "service": "YellowPages API",
            "version": "1.0.0",
            "docs": "/docs",
        }
else:
    @app.get("/", tags=["服务根路径"])
    async def root():
        return {
            "service": "YellowPages API",
            "version": "1.0.0",
            "docs": "/docs",
            "openapi": "/openapi.json",
        }

if __name__ == "__main__":
    uvicorn.run("app.main:app", host="0.0.0.0", port=8080, reload=True)
