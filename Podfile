platform :ios, '26.0'
use_frameworks!

target 'Mojigai' do
  # 微信朋友圈式图片浏览器:缩放/下拉关闭/翻页现成实现(2020 年后停更的最终版 3.0.9)
  pod 'YBImageBrowser', '~> 3.0.9'
  # FFmpegKit（8 种变体选其一，按需替换）：
  #   ffmpeg-kit-ios-min / ffmpeg-kit-ios-min-gpl
  #   ffmpeg-kit-ios-https / ffmpeg-kit-ios-https-gpl
  #   ffmpeg-kit-ios-audio / ffmpeg-kit-ios-video
  #   ffmpeg-kit-ios-full / ffmpeg-kit-ios-full-gpl
  pod 'ffmpeg-kit-ios-full', :podspec => 'https://raw.githubusercontent.com/luthviar/ffmpeg-kit-ios-full/main/ffmpeg-kit-ios-full.podspec'
end

# 老 pod 的部署目标(8.0/9.0/12.0)低于现代 SDK 下限,统一抬到 15.0
post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
    end
  end
end
