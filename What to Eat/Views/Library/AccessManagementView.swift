import AVFoundation
import CoreLocation
import Photos
import SwiftUI
import UIKit

struct AccessManagementView: View {
    @EnvironmentObject private var appContainer: AppContainer
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var photosStatus: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @State private var cameraStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            MealCoachBackground()

            Form {
                Section {
                    Text(healthStatusText)
                        .foregroundStyle(MealCoachTheme.secondaryInk)

                    Text(LocalizedText.ui("Workout data access is included in Health access.", "运动数据权限包含在健康权限中。"))
                        .font(.footnote)
                        .foregroundStyle(MealCoachTheme.secondaryInk)

                    HStack(spacing: 10) {
                        Button(LocalizedText.ui("Request Health Access", "请求健康权限")) {
                            requestHealthAccess()
                        }
                        .buttonStyle(MealCoachPrimaryButtonStyle(startColor: MealCoachTheme.navy, endColor: MealCoachTheme.teal))

                        Button(LocalizedText.ui("Open Settings", "打开设置")) {
                            openAppSettings()
                        }
                        .buttonStyle(MealCoachSecondaryButtonStyle(tint: MealCoachTheme.coral))
                    }
                } header: {
                    sectionHeader(LocalizedText.ui("Health & Workouts", "健康与运动"))
                }
                .listRowBackground(MealCoachTheme.listRowBackground)

                Section {
                    Text(photoStatusText)
                        .foregroundStyle(MealCoachTheme.secondaryInk)

                    HStack(spacing: 10) {
                        Button(LocalizedText.ui("Request Photo Access", "请求照片权限")) {
                            requestPhotoAccess()
                        }
                        .buttonStyle(MealCoachPrimaryButtonStyle(startColor: MealCoachTheme.teal, endColor: MealCoachTheme.navy))

                        Button(LocalizedText.ui("Open Settings", "打开设置")) {
                            openAppSettings()
                        }
                        .buttonStyle(MealCoachSecondaryButtonStyle(tint: MealCoachTheme.coral))
                    }
                } header: {
                    sectionHeader(LocalizedText.ui("Photos", "照片"))
                }
                .listRowBackground(MealCoachTheme.listRowBackground)

                Section {
                    Text(cameraStatusText)
                        .foregroundStyle(MealCoachTheme.secondaryInk)

                    HStack(spacing: 10) {
                        Button(LocalizedText.ui("Request Camera Access", "请求相机权限")) {
                            requestCameraAccess()
                        }
                        .buttonStyle(MealCoachPrimaryButtonStyle(startColor: MealCoachTheme.navy, endColor: MealCoachTheme.coral))

                        Button(LocalizedText.ui("Open Settings", "打开设置")) {
                            openAppSettings()
                        }
                        .buttonStyle(MealCoachSecondaryButtonStyle(tint: MealCoachTheme.coral))
                    }
                } header: {
                    sectionHeader(LocalizedText.ui("Camera", "相机"))
                }
                .listRowBackground(MealCoachTheme.listRowBackground)

                Section {
                    Text(locationStatusText)
                        .foregroundStyle(MealCoachTheme.secondaryInk)

                    HStack(spacing: 10) {
                        Button(LocalizedText.ui("Request Location Access", "请求定位权限")) {
                            appContainer.locationManager.requestWhenInUsePermission()
                        }
                        .buttonStyle(MealCoachPrimaryButtonStyle(startColor: MealCoachTheme.coral, endColor: MealCoachTheme.amber))

                        Button(LocalizedText.ui("Open Settings", "打开设置")) {
                            openAppSettings()
                        }
                        .buttonStyle(MealCoachSecondaryButtonStyle(tint: MealCoachTheme.coral))
                    }
                } header: {
                    sectionHeader(LocalizedText.ui("Location (GPS)", "定位（GPS）"))
                }
                .listRowBackground(MealCoachTheme.listRowBackground)

                Section {
                    Text(
                        LocalizedText.ui(
                            "You can grant permissions here. iOS requires revoking permissions in the system Settings app.",
                            "你可以在此授予权限；如需取消权限，iOS 要求在系统“设置”中操作。"
                        )
                    )
                    .font(.footnote)
                    .foregroundStyle(MealCoachTheme.secondaryInk)
                }
                .listRowBackground(MealCoachTheme.listRowBackground)

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                    .listRowBackground(MealCoachTheme.listRowBackground)
                }
            }
            .foregroundStyle(MealCoachTheme.ink)
            .scrollContentBackground(.hidden)
            .listStyle(.insetGrouped)
        }
        .navigationTitle(LocalizedText.ui("Access Management", "权限管理"))
        .onAppear {
            refreshStatuses()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            refreshStatuses()
        }
    }

    private var healthStatusText: String {
        switch appContainer.healthKitManager.permissionState {
        case .authorized:
            return LocalizedText.ui("Health access: granted.", "健康权限：已授予。")
        case .denied:
            return LocalizedText.ui("Health access: denied.", "健康权限：已拒绝。")
        case .unavailable:
            return LocalizedText.ui("Health access: unavailable on this device.", "健康权限：此设备不可用。")
        case .unknown:
            return LocalizedText.ui("Health access: not requested yet.", "健康权限：尚未请求。")
        }
    }

    private var photoStatusText: String {
        switch photosStatus {
        case .authorized:
            return LocalizedText.ui("Photo access: granted.", "照片权限：已授予。")
        case .limited:
            return LocalizedText.ui("Photo access: limited.", "照片权限：部分授予。")
        case .denied, .restricted:
            return LocalizedText.ui("Photo access: denied.", "照片权限：已拒绝。")
        case .notDetermined:
            return LocalizedText.ui("Photo access: not requested yet.", "照片权限：尚未请求。")
        @unknown default:
            return LocalizedText.ui("Photo access: unknown status.", "照片权限：未知状态。")
        }
    }

    private var cameraStatusText: String {
        switch cameraStatus {
        case .authorized:
            return LocalizedText.ui("Camera access: granted.", "相机权限：已授予。")
        case .denied, .restricted:
            return LocalizedText.ui("Camera access: denied.", "相机权限：已拒绝。")
        case .notDetermined:
            return LocalizedText.ui("Camera access: not requested yet.", "相机权限：尚未请求。")
        @unknown default:
            return LocalizedText.ui("Camera access: unknown status.", "相机权限：未知状态。")
        }
    }

    private var locationStatusText: String {
        switch appContainer.locationManager.authorizationStatus {
        case .authorizedAlways:
            return LocalizedText.ui("Location access: always.", "定位权限：始终允许。")
        case .authorizedWhenInUse:
            return LocalizedText.ui("Location access: while using app.", "定位权限：使用 App 期间允许。")
        case .denied, .restricted:
            return LocalizedText.ui("Location access: denied.", "定位权限：已拒绝。")
        case .notDetermined:
            return LocalizedText.ui("Location access: not requested yet.", "定位权限：尚未请求。")
        @unknown default:
            return LocalizedText.ui("Location access: unknown status.", "定位权限：未知状态。")
        }
    }

    private func requestHealthAccess() {
        Task {
            _ = await appContainer.healthKitManager.requestAuthorization()
        }
    }

    private func requestPhotoAccess() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            Task { @MainActor in
                photosStatus = status
            }
        }
    }

    private func requestCameraAccess() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraStatus = .authorized
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    cameraStatus = granted ? .authorized : .denied
                }
            }
        case .denied, .restricted:
            cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        @unknown default:
            cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            errorMessage = LocalizedText.ui("Unable to open Settings.", "无法打开设置。")
            return
        }
        openURL(url)
    }

    private func refreshStatuses() {
        photosStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .foregroundStyle(MealCoachTheme.ink)
            .textCase(nil)
    }
}
