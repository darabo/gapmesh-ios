require 'xcodeproj'
project_path = '/Users/darabonakdar/gapmesh-ios/GapMesh.xcodeproj'
project = Xcodeproj::Project.open(project_path)

puts "Updating ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS for gap_iOS..."
# 1. Update gap_iOS target build settings for All AppIcons
bitchat_target = project.targets.find { |t| t.name == 'gap_iOS' }
if bitchat_target
  bitchat_target.build_configurations.each do |config|
    config.build_settings['ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS'] = 'YES'
  end
  puts "Updated gap_iOS."
else
  puts "Target 'gap_iOS' not found."
end

puts "Checking Gap MeshExtension App Group entitlements..."
# 2. Add CODE_SIGN_ENTITLEMENTS to Gap MeshExtension
ext_target = project.targets.find { |t| t.name == 'Gap MeshExtension' }
if ext_target
  # Create an entitlements file if it doesn't easily exist or just link bitchat.entitlements
  # The extension needs group.chat.gap.kevahazadi. We can just use the main app's entitlements for now
  # or point to a new file. bitchat/bitchat.entitlements already has the app group!
  
  entitlements_path = "bitchat/bitchat.entitlements"
  
  ext_target.build_configurations.each do |config|
    config.build_settings['CODE_SIGN_ENTITLEMENTS'] = entitlements_path
  end
  puts "Linked entitlements to Gap MeshExtension."
else
  puts "Target 'Gap MeshExtension' not found."
end

project.save
puts "Project saved successfully."
