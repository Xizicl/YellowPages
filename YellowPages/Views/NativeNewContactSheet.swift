import SwiftUI
import Contacts
#if canImport(UIKit)
import UIKit
#endif
#if canImport(ContactsUI) && (os(iOS) || targetEnvironment(macCatalyst))
import ContactsUI
#endif

/// 零权限原生系统“新建联系人”页面包装器
/// 基于苹果 ContactsUI CNContactViewController(forNewContact:)
/// 在独立系统沙盒流程中呈现，用户自行决定保存或取消，App 自身零隐私权限索取
public struct NativeNewContactSheet: UIViewControllerRepresentable {
    public let contact: CNContact
    public var onComplete: () -> Void

    public init(contact: CNContact, onComplete: @escaping () -> Void) {
        self.contact = contact
        self.onComplete = onComplete
    }

    /// 便捷构造工厂：根据号码与建议标签创建预填 contact
    public static func makeContact(name: String, phoneNumber: String, note: String? = nil) -> CNMutableContact {
        let mutableContact = CNMutableContact()
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        mutableContact.givenName = trimmedName.isEmpty ? "未命名联系人" : trimmedName

        let cleanPhone = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanPhone.isEmpty {
            let phoneValue = CNPhoneNumber(stringValue: cleanPhone)
            let labeledValue = CNLabeledValue(label: CNLabelPhoneNumberMobile, value: phoneValue)
            mutableContact.phoneNumbers = [labeledValue]
        }

        if let note = note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            mutableContact.note = note
        }

        return mutableContact
    }

    #if canImport(ContactsUI) && (os(iOS) || targetEnvironment(macCatalyst))
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeUIViewController(context: Context) -> UINavigationController {
        let contactVC = CNContactViewController(forNewContact: contact)
        contactVC.delegate = context.coordinator
        
        let navController = UINavigationController(rootViewController: contactVC)
        return navController
    }

    public func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    public final class Coordinator: NSObject, CNContactViewControllerDelegate {
        let parent: NativeNewContactSheet

        init(_ parent: NativeNewContactSheet) {
            self.parent = parent
        }

        public func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
            // 系统新建联系人操作完成（无论用户点击完成还是取消），通知外层关闭
            parent.onComplete()
        }
    }
    #else
    public func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    public func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
    #endif
}
