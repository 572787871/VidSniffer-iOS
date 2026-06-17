Pod::Spec.new do |s|
  s.name = 'FFmpeg'
  s.version = '1.0.0'
  s.summary = 'Local offline FFmpegKit framework for VidSniffer Pro.'
  s.description = 'Offline vendored FFmpeg.xcframework. Place the enterprise/self-signed FFmpegKit-compatible binary at ios/FFmpeg/FFmpeg.xcframework.'
  s.homepage = 'https://example.invalid/vidsniffer-pro-ffmpeg'
  s.license = { :type => 'GPL' }
  s.author = { 'VidSniffer Pro' => 'local@example.invalid' }
  s.platform = :ios, '15.0'
  s.source = { :path => '.' }
  s.vendored_frameworks = 'FFmpeg.xcframework'
  s.module_name = 'FFmpeg'
end
