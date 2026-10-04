#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint speaker_tone_engine.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'speaker_tone_engine'
  s.version          = '0.1.0'
  s.summary          = 'Low-level iOS tone engine (AVAudioEngine + AVAudioSourceNode) that renders procedurally generated tone programs in real time.'
  s.description      = <<-DESC
Low-level iOS tone engine (AVAudioEngine + AVAudioSourceNode) that renders procedurally generated tone programs in real time.
                       DESC
  s.homepage         = 'https://github.com/mihok/ultrasonic-app'
  s.license          = { :type => 'Proprietary', :text => 'Part of ultrasonic-app.' }
  s.author           = { 'mihok' => 'https://github.com/mihok' }
  s.source           = { :path => '.' }
  s.source_files = 'speaker_tone_engine/Sources/speaker_tone_engine/**/*'
  s.dependency 'Flutter'
  s.frameworks = 'AVFoundation', 'QuartzCore'
  s.platform = :ios, '15.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'speaker_tone_engine_privacy' => ['speaker_tone_engine/Sources/speaker_tone_engine/PrivacyInfo.xcprivacy']}
end
