//
//  Generated file. Do not edit.
//

// clang-format off

#import "GeneratedPluginRegistrant.h"

#if __has_include(<integration_test/IntegrationTestPlugin.h>)
#import <integration_test/IntegrationTestPlugin.h>
#else
@import integration_test;
#endif

#if __has_include(<native_camera_view/NativeCameraViewPlugin.h>)
#import <native_camera_view/NativeCameraViewPlugin.h>
#else
@import native_camera_view;
#endif

@implementation GeneratedPluginRegistrant

+ (void)registerWithRegistry:(NSObject<FlutterPluginRegistry>*)registry {
  [IntegrationTestPlugin registerWithRegistrar:[registry registrarForPlugin:@"IntegrationTestPlugin"]];
  [NativeCameraViewPlugin registerWithRegistrar:[registry registrarForPlugin:@"NativeCameraViewPlugin"]];
}

@end
