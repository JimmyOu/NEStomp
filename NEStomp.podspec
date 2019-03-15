#
#  Be sure to run `pod spec lint NEStomp.podspec' to ensure this is a
#  valid spec and to remove all comments including this before submitting the spec.
#
#  To learn more about Podspec attributes see https://docs.cocoapods.org/specification.html
#  To see working Podspecs in the CocoaPods repo see https://github.com/CocoaPods/Specs/
#

Pod::Spec.new do |s|

s.name         = "NEStomp"
s.version      = "0.0.1"
s.license      = "MIT"
s.summary      = "基于Stomp数据传输协议 和 WebSocket封装的一个库"


s.homepage     = "https://github.com/JimmyOu"
s.source       = { :git => "https://github.com/JimmyOu/NEStomp.git", :tag => "#{s.version}" }
s.source_files  = "NEStomp/*.{h,m}"
s.requires_arc = true
s.platform     = :ios, "8.0"
s.frameworks = "Foundation"

s.dependency 'SocketRocket', '~> 0.5.1'

s.author             = { "姜欧" => "15757175841@163.com" } # 作者信息

end
