//
//  NotifExp.swift
//  shukr
//
//  Created by Izhan S Ansari on 12/3/24.
//


import SwiftUI
import UserNotifications

struct NotifExp: View {
    @State private var notificationPermission = false
    @State private var notificationMessage = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Notification Example")
                .font(.title)
            
            Button("Request Permission") {
                requestNotificationPermission()
            }
            
            TextField("Notification Message", text: $notificationMessage)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
            
            Button("Schedule Notification") {
                scheduleNotification()
            }
            .disabled(!notificationPermission || notificationMessage.isEmpty)
            
            Text("Permission Status: \(notificationPermission ? "Granted" : "Not Granted")")
                .font(.caption)
        }
        .padding()
        .onAppear {
            checkNotificationPermission()
        }
    }
    
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { success, error in
            if success {
                print("Permission granted")
                notificationPermission = true
            } else if let error = error {
                print(error.localizedDescription)
            }
        }
    }
    
    func checkNotificationPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                notificationPermission = (settings.authorizationStatus == .authorized)
            }
        }
    }
    
    func scheduleNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Notification"
        content.body = notificationMessage
        content.sound = UNNotificationSound.default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling notification: \(error.localizedDescription)")
            } else {
                print("Notification scheduled successfully")
            }
        }
    }
}

struct NotifExp_Previews: PreviewProvider {
    static var previews: some View {
        NotifExp()
    }
}
