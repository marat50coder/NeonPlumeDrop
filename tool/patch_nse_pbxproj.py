#!/usr/bin/env python3
"""Wire OrbitPulseService + PrivacyInfo + GoogleService into project.pbxproj."""

from pathlib import Path

PBX = Path("/Users/imoortal/flutter_projects/NeonPlumeDrop/ios/Runner.xcodeproj/project.pbxproj")

GOOGLE_REF = "8082C7908DC2F9C65AE43491"
PRIVACY_REF = "79C8AFF3CE07434E8556950D"
ENTITLEMENTS_REF = "9A91EF0A6611025EDA50E19F"
NSE_SWIFT_REF = "4CD11CBA066FA58C57D982B1"
NSE_PLIST_REF = "BC1F183F23D2BB080551D170"
NSE_APPEX_REF = "077590E3846C5DB9E7983EEC"
GOOGLE_BUILD = "67AEDB9640915643C476F7D9"
PRIVACY_BUILD = "24A95AC43873D6DA78EFFFD1"
NSE_SWIFT_BUILD = "469E1EEE655FAA48105289FF"
NSE_EMBED_BUILD = "17DAFB4DBF88CCB0F875A409"
NSE_GROUP = "B29DCD0392116308DFB90289"
NSE_TARGET = "849209054EF331D5DDC3E280"
NSE_PROXY = "02A27802E7B170522F719226"
NSE_DEPENDENCY = "D7F7F3C33C95611E015F22D9"
EMBED_PHASE = "A1147D0D15FA46A5AF906151"
NSE_SOURCES = "D808B6BB595967DAD00F155E"
NSE_FRAMEWORKS = "38905FF9A6540CD67DC5B88E"
NSE_RESOURCES = "BE03FA81C2DC1C5E2F4FA65B"
NSE_DEBUG = "5A92AB2BC0641C21B30A8F59"
NSE_RELEASE = "3EEDEE8E586C5F40F136C3CF"
NSE_PROFILE = "DC4BADCD7DFCD835220F4658"
NSE_CFG_LIST = "76B332F286EFB1C4F96AEC7E"


def once(text: str, old: str, new: str) -> str:
    if new.split("\n", 1)[0] in text and old not in text:
        return text
    if old not in text:
        raise SystemExit(f"anchor not found:\n{old[:120]}")
    return text.replace(old, new, 1)


def main() -> None:
    text = PBX.read_bytes().decode("utf-8")
    if "OrbitPulseService" in text and "PrivacyInfo.xcprivacy in Resources" in text:
        print("already patched")
        return

    text = once(
        text,
        "/* End PBXBuildFile section */",
        f"""\t\t{GOOGLE_BUILD} /* GoogleService-Info.plist in Resources */ = {{isa = PBXBuildFile; fileRef = {GOOGLE_REF} /* GoogleService-Info.plist */; }};
		{PRIVACY_BUILD} /* PrivacyInfo.xcprivacy in Resources */ = {{isa = PBXBuildFile; fileRef = {PRIVACY_REF} /* PrivacyInfo.xcprivacy */; }};
		{NSE_SWIFT_BUILD} /* NotificationService.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {NSE_SWIFT_REF} /* NotificationService.swift */; }};
		{NSE_EMBED_BUILD} /* OrbitPulseService.appex in Embed App Extensions */ = {{isa = PBXBuildFile; fileRef = {NSE_APPEX_REF} /* OrbitPulseService.appex */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};
/* End PBXBuildFile section */""",
    )

    text = once(
        text,
        "/* End PBXContainerItemProxy section */",
        f"""\t\t{NSE_PROXY} /* PBXContainerItemProxy */ = {{
			isa = PBXContainerItemProxy;
			containerPortal = 97C146E61CF9000F007C117D /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = {NSE_TARGET};
			remoteInfo = OrbitPulseService;
		}};
/* End PBXContainerItemProxy section */""",
    )

    text = once(
        text,
        "/* Begin PBXCopyFilesBuildPhase section */\n",
        f"""/* Begin PBXCopyFilesBuildPhase section */
		{EMBED_PHASE} /* Embed App Extensions */ = {{
			isa = PBXCopyFilesBuildPhase;
			buildActionMask = 2147483647;
			dstPath = "";
			dstSubfolderSpec = 13;
			files = (
				{NSE_EMBED_BUILD} /* OrbitPulseService.appex in Embed App Extensions */,
			);
			name = "Embed App Extensions";
			runOnlyForDeploymentPostprocessing = 0;
		}};
""",
    )

    text = once(
        text,
        "/* End PBXFileReference section */",
        f"""\t\t{GOOGLE_REF} /* GoogleService-Info.plist */ = {{isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = text.plist.xml; path = "GoogleService-Info.plist"; sourceTree = "<group>"; }};
		{PRIVACY_REF} /* PrivacyInfo.xcprivacy */ = {{isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = text.plist.xml; path = PrivacyInfo.xcprivacy; sourceTree = "<group>"; }};
		{ENTITLEMENTS_REF} /* Runner.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = Runner.entitlements; sourceTree = "<group>"; }};
		{NSE_SWIFT_REF} /* NotificationService.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = NotificationService.swift; sourceTree = "<group>"; }};
		{NSE_PLIST_REF} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; }};
		{NSE_APPEX_REF} /* OrbitPulseService.appex */ = {{isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = OrbitPulseService.appex; sourceTree = BUILT_PRODUCTS_DIR; }};
/* End PBXFileReference section */""",
    )

    text = once(
        text,
        "/* End PBXFrameworksBuildPhase section */",
        f"""\t\t{NSE_FRAMEWORKS} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXFrameworksBuildPhase section */""",
    )

    text = once(
        text,
        """\t\t97C146E51CF9000F007C117D = {
			isa = PBXGroup;
			children = (
				9740EEB11CF90186004384FC /* Flutter */,
				97C146F01CF9000F007C117D /* Runner */,
				97C146EF1CF9000F007C117D /* Products */,
				331C8082294A63A400263BE5 /* RunnerTests */,
				C2682AA39B6C32C97B0A82C2 /* Pods */,
				940646F8DD7B38E2DA6DB4A5 /* Frameworks */,
			);""",
        f"""\t\t97C146E51CF9000F007C117D = {{
			isa = PBXGroup;
			children = (
				9740EEB11CF90186004384FC /* Flutter */,
				97C146F01CF9000F007C117D /* Runner */,
				{NSE_GROUP} /* OrbitPulseService */,
				97C146EF1CF9000F007C117D /* Products */,
				331C8082294A63A400263BE5 /* RunnerTests */,
				C2682AA39B6C32C97B0A82C2 /* Pods */,
				940646F8DD7B38E2DA6DB4A5 /* Frameworks */,
			);""",
    )

    text = once(
        text,
        """\t\t97C146EF1CF9000F007C117D /* Products */ = {
			isa = PBXGroup;
			children = (
				97C146EE1CF9000F007C117D /* Runner.app */,
				331C8081294A63A400263BE5 /* RunnerTests.xctest */,
			);""",
        f"""\t\t97C146EF1CF9000F007C117D /* Products */ = {{
			isa = PBXGroup;
			children = (
				97C146EE1CF9000F007C117D /* Runner.app */,
				331C8081294A63A400263BE5 /* RunnerTests.xctest */,
				{NSE_APPEX_REF} /* OrbitPulseService.appex */,
			);""",
    )

    text = once(
        text,
        """\t\t\t\t74858FAD1ED2DC5600515810 /* Runner-Bridging-Header.h */,
			);
			path = Runner;""",
        f"""\t\t\t\t74858FAD1ED2DC5600515810 /* Runner-Bridging-Header.h */,
				{GOOGLE_REF} /* GoogleService-Info.plist */,
				{PRIVACY_REF} /* PrivacyInfo.xcprivacy */,
				{ENTITLEMENTS_REF} /* Runner.entitlements */,
			);
			path = Runner;""",
    )

    text = once(
        text,
        "/* End PBXGroup section */",
        f"""\t\t{NSE_GROUP} /* OrbitPulseService */ = {{
			isa = PBXGroup;
			children = (
				{NSE_SWIFT_REF} /* NotificationService.swift */,
				{NSE_PLIST_REF} /* Info.plist */,
			);
			path = OrbitPulseService;
			sourceTree = "<group>";
		}};
/* End PBXGroup section */""",
    )

    text = once(
        text,
        "/* Begin PBXNativeTarget section */\n",
        f"""/* Begin PBXNativeTarget section */
		{NSE_TARGET} /* OrbitPulseService */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {NSE_CFG_LIST} /* Build configuration list for PBXNativeTarget "OrbitPulseService" */;
			buildPhases = (
				{NSE_SOURCES} /* Sources */,
				{NSE_FRAMEWORKS} /* Frameworks */,
				{NSE_RESOURCES} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = OrbitPulseService;
			productName = OrbitPulseService;
			productReference = {NSE_APPEX_REF} /* OrbitPulseService.appex */;
			productType = "com.apple.product-type.app-extension";
		}};
""",
    )

    text = once(
        text,
        """\t\t\t\t97C146EC1CF9000F007C117D /* Resources */,
				9705A1C41CF9048500538489 /* Embed Frameworks */,
				3B06AD1E1E4923F5004D2608 /* Thin Binary */,""",
        f"""\t\t\t\t97C146EC1CF9000F007C117D /* Resources */,
				9705A1C41CF9048500538489 /* Embed Frameworks */,
				{EMBED_PHASE} /* Embed App Extensions */,
				3B06AD1E1E4923F5004D2608 /* Thin Binary */,""",
    )

    text = once(
        text,
        """\t\t\tbuildRules = (
			);
			dependencies = (
			);
			name = Runner;""",
        f"""\t\t\tbuildRules = (
			);
			dependencies = (
				{NSE_DEPENDENCY} /* PBXTargetDependency */,
			);
			name = Runner;""",
    )

    text = once(
        text,
        """\t\t\t\t\t97C146ED1CF9000F007C117D = {
						CreatedOnToolsVersion = 7.3.1;
						LastSwiftMigration = 1100;
					};""",
        f"""\t\t\t\t\t97C146ED1CF9000F007C117D = {{
						CreatedOnToolsVersion = 7.3.1;
						LastSwiftMigration = 1100;
					}};
					{NSE_TARGET} = {{
						CreatedOnToolsVersion = 16.0;
					}};""",
    )

    text = once(
        text,
        """\t\t\ttargets = (
				97C146ED1CF9000F007C117D /* Runner */,
				331C8080294A63A400263BE5 /* RunnerTests */,
			);""",
        f"""\t\t\ttargets = (
				97C146ED1CF9000F007C117D /* Runner */,
				331C8080294A63A400263BE5 /* RunnerTests */,
				{NSE_TARGET} /* OrbitPulseService */,
			);""",
    )

    text = once(
        text,
        """\t\t\tfiles = (
				97C147011CF9000F007C117D /* LaunchScreen.storyboard in Resources */,
				3B3967161E833CAA004F5970 /* AppFrameworkInfo.plist in Resources */,
				97C146FE1CF9000F007C117D /* Assets.xcassets in Resources */,
				97C146FC1CF9000F007C117D /* Main.storyboard in Resources */,
			);""",
        f"""\t\t\tfiles = (
				97C147011CF9000F007C117D /* LaunchScreen.storyboard in Resources */,
				3B3967161E833CAA004F5970 /* AppFrameworkInfo.plist in Resources */,
				97C146FE1CF9000F007C117D /* Assets.xcassets in Resources */,
				97C146FC1CF9000F007C117D /* Main.storyboard in Resources */,
				{GOOGLE_BUILD} /* GoogleService-Info.plist in Resources */,
				{PRIVACY_BUILD} /* PrivacyInfo.xcprivacy in Resources */,
			);""",
    )

    text = once(
        text,
        "/* End PBXResourcesBuildPhase section */",
        f"""\t\t{NSE_RESOURCES} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXResourcesBuildPhase section */""",
    )

    text = once(
        text,
        "/* End PBXSourcesBuildPhase section */",
        f"""\t\t{NSE_SOURCES} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{NSE_SWIFT_BUILD} /* NotificationService.swift in Sources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXSourcesBuildPhase section */""",
    )

    text = once(
        text,
        "/* End PBXTargetDependency section */",
        f"""\t\t{NSE_DEPENDENCY} /* PBXTargetDependency */ = {{
			isa = PBXTargetDependency;
			target = {NSE_TARGET} /* OrbitPulseService */;
			targetProxy = {NSE_PROXY} /* PBXContainerItemProxy */;
		}};
/* End PBXTargetDependency section */""",
    )

    nse_cfg = f"""		{NSE_DEBUG} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 9;
				DEVELOPMENT_TEAM = L6C2DFLMGM;
				ENABLE_BITCODE = NO;
				INFOPLIST_FILE = OrbitPulseService/Info.plist;
				IPHONEOS_DEPLOYMENT_TARGET = 15.0;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
					"@executable_path/../../Frameworks",
				);
				MARKETING_VERSION = 1.0.3;
				PRODUCT_BUNDLE_IDENTIFIER = com.neonplumedrop.neonplumedropgame.NotificationService;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SDKROOT = iphoneos;
				SKIP_INSTALL = YES;
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			}};
			name = Debug;
		}};
		{NSE_RELEASE} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 9;
				DEVELOPMENT_TEAM = L6C2DFLMGM;
				ENABLE_BITCODE = NO;
				INFOPLIST_FILE = OrbitPulseService/Info.plist;
				IPHONEOS_DEPLOYMENT_TARGET = 15.0;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
					"@executable_path/../../Frameworks",
				);
				MARKETING_VERSION = 1.0.3;
				PRODUCT_BUNDLE_IDENTIFIER = com.neonplumedrop.neonplumedropgame.NotificationService;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SDKROOT = iphoneos;
				SKIP_INSTALL = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			}};
			name = Release;
		}};
		{NSE_PROFILE} /* Profile */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 9;
				DEVELOPMENT_TEAM = L6C2DFLMGM;
				ENABLE_BITCODE = NO;
				INFOPLIST_FILE = OrbitPulseService/Info.plist;
				IPHONEOS_DEPLOYMENT_TARGET = 15.0;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
					"@executable_path/../../Frameworks",
				);
				MARKETING_VERSION = 1.0.3;
				PRODUCT_BUNDLE_IDENTIFIER = com.neonplumedrop.neonplumedropgame.NotificationService;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SDKROOT = iphoneos;
				SKIP_INSTALL = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			}};
			name = Profile;
		}};
"""

    text = once(text, "/* End XCBuildConfiguration section */", nse_cfg + "/* End XCBuildConfiguration section */")

    text = once(
        text,
        "/* End XCConfigurationList section */",
        f"""\t\t{NSE_CFG_LIST} /* Build configuration list for PBXNativeTarget "OrbitPulseService" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{NSE_DEBUG} /* Debug */,
				{NSE_RELEASE} /* Release */,
				{NSE_PROFILE} /* Profile */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
/* End XCConfigurationList section */""",
    )

    for uid in (
        "97C147061CF9000F007C117D",
        "97C147071CF9000F007C117D",
        "249021D4217E4FDB00AE95B9",
    ):
        marker = f"{uid} /* "
        start = text.find(marker)
        if start < 0:
            raise SystemExit(f"missing runner cfg {uid}")
        end = text.find("name = ", start)
        block = text[start:end]
        if "CODE_SIGN_ENTITLEMENTS" not in block:
            block = block.replace(
                "CLANG_ENABLE_MODULES = YES;\n",
                "CLANG_ENABLE_MODULES = YES;\n\t\t\t\tCODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;\n",
            )
        block = block.replace("DEVELOPMENT_TEAM = 28UWA86D42;", "DEVELOPMENT_TEAM = L6C2DFLMGM;")
        text = text[:start] + block + text[end:]

    text = text.replace("IPHONEOS_DEPLOYMENT_TARGET = 13.0;", "IPHONEOS_DEPLOYMENT_TARGET = 15.0;")

    g_start = text.find("/* Begin PBXGroup section */")
    g_end = text.find("/* End PBXGroup section */")
    assert NSE_GROUP in text[g_start:g_end], "NSE group outside PBXGroup section"
    assert text.count("CODE_SIGN_ENTITLEMENTS") == 3
    for uid in (NSE_DEBUG, NSE_RELEASE, NSE_PROFILE):
        idx = text.find(uid)
        chunk = text[idx : idx + 1400]
        assert "CODE_SIGN_ENTITLEMENTS" not in chunk
        assert "baseConfigurationReference" not in chunk

    PBX.write_bytes(text.encode("utf-8"))
    print("pbxproj patched")


if __name__ == "__main__":
    main()
