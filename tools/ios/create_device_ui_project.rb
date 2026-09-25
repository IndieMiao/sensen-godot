#!/usr/bin/env ruby
# Generate a separate XCTest UI runner for an already-installed Journey app.
require 'fileutils'
require 'xcodeproj'

output, team = ARGV
abort 'Usage: create_device_ui_project.rb OUTPUT_DIRECTORY TEAM_ID' unless output && team
abort 'Invalid Apple Team ID' unless team.match?(/\A[A-Z0-9]{10}\z/)
output = File.expand_path(output)
FileUtils.mkdir_p(output)
project_path = File.join(output, 'JourneyDeviceQA.xcodeproj')
abort "Project already exists: #{project_path}" if File.exist?(project_path)

project = Xcodeproj::Project.new(project_path)
target = project.new_target(:ui_test_bundle, 'JourneyDeviceUITests', :ios, '15.0')
source = File.expand_path('../../tests/ios/JourneyDeviceUITests.swift', __dir__)
reference = project.main_group.new_file(source)
target.source_build_phase.add_file_reference(reference)
target.build_configurations.each do |configuration|
  configuration.build_settings.merge!({
    'CODE_SIGN_STYLE' => 'Automatic',
    'CODE_SIGN_IDENTITY' => 'Apple Development',
    'DEVELOPMENT_TEAM' => team,
    'PRODUCT_BUNDLE_IDENTIFIER' => 'app.gensen.maps.deviceuitests',
    'GENERATE_INFOPLIST_FILE' => 'YES',
    'SWIFT_VERSION' => '5.0',
    'TARGETED_DEVICE_FAMILY' => '1,2',
    'ENABLE_TESTING_SEARCH_PATHS' => 'YES',
    'SUPPORTED_PLATFORMS' => 'iphoneos iphonesimulator',
    'SUPPORTS_MACCATALYST' => 'NO',
  })
end
project.save

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(target)
scheme.add_test_target(target)
scheme.test_action.build_configuration = 'Debug'
scheme.save_as(project_path, 'JourneyDeviceQA', true)
puts project_path
