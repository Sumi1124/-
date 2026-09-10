#!/usr/bin/env python3
"""Generates SourceDesk.xcodeproj/project.pbxproj (classic objectVersion 56 format)
so the app builds with SwiftData in Xcode 15+."""
import os, uuid, hashlib

ROOT = os.path.abspath(os.path.dirname(os.path.abspath(__file__)) + "/..")
APP_DIR = os.path.join(ROOT, "SourceDesk")
TEST_DIR = os.path.join(ROOT, "SourceDeskTests")

def uid(seed):
    h = hashlib.sha256(seed.encode()).hexdigest().upper()[:24]
    return h

def walk_files(base):
    result = []
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames[:] = [d for d in dirnames if d not in (".build",)]
        for f in sorted(filenames):
            if f.endswith(".swift"):
                full = os.path.join(dirpath, f)
                rel = os.path.relpath(full, ROOT)
                result.append((full, rel))
    return sorted(result, key=lambda x: x[1])

app_files = walk_files(APP_DIR)
test_files = walk_files(TEST_DIR)

# --- IDs ---
PROJECT_ID = uid("project")
MAIN_GROUP = uid("main_group")
APP_TARGET = uid("app_target")
TEST_TARGET = uid("test_target")
APP_PRODUCT = uid("app_product")
TEST_PRODUCT = uid("test_product")
APP_PHASE = uid("app_phase")
TEST_PHASE = uid("test_phase")
APP_SOURCES_GROUP = uid("app_sources_group")
TEST_SOURCES_GROUP = uid("test_sources_group")
PRODUCTS_GROUP = uid("products_group")
APP_CONFIG_LIST = uid("app_config_list")
TEST_CONFIG_LIST = uid("test_config_list")
PROJ_CONFIG_LIST = uid("proj_config_list")
PROXY_ID = uid("proxy_item")
DEP_ID = uid("dep")
BUILD_CONFIGS = [uid(f"config_{i}") for i in range(6)]  # app_db, app_r, test_db, test_r, proj_db, proj_r
FRAMEWORKS_PHASE_APP = uid("frameworks_app")
FRAMEWORKS_PHASE_TEST = uid("frameworks_test")
SOURCES_PHASE_APP = uid("sources_app")
SOURCES_PHASE_TEST = uid("sources_test")
RESOURCES_PHASE_APP = uid("resources_app")

PBX_LINE = ""

file_ids = {}
for full, rel in app_files + test_files:
    file_ids[rel] = uid("file_" + rel)

ASSET_ID = uid("file_assets")
ASSET_BUILD = uid("build_asset")

def pbx_file_refs():
    refs = []
    for full, rel in app_files + test_files:
        fid = file_ids[rel]
        name = os.path.basename(full)
        path = os.path.join("SourceDesk" if full.startswith(APP_DIR) else "SourceDeskTests", name)
        refs.append(f"\t\t{fid} /* {name} in Sources */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {path}; sourceTree = \"<group>\"; }};")
    refs.append(f"\t\t{ASSET_ID} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = \"Resources/Assets.xcassets\"; sourceTree = \"<group>\"; }};")
    refs.append(f"\t\t{APP_PRODUCT} /* SourceDesk.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = SourceDesk.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
    refs.append(f"\t\t{TEST_PRODUCT} /* SourceDeskTests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = SourceDeskTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};")
    builds = f"\t\t{ASSET_BUILD} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {ASSET_ID} /* Assets.xcassets */; }};"
    return f"""/* Begin PBXBuildFile section */
{builds}
/* End PBXBuildFile section */
/* Begin PBXFileReference section */
{chr(10).join(refs)}
/* End PBXFileReference section */"""

def pbx_groups():
    children = []
    for full, rel in app_files:
        children.append(f"\t\t\t\t{file_ids[rel]} /* {os.path.basename(full)} */,")
    children.append(f"\t\t\t\t{ASSET_ID} /* Assets.xcassets */,")
    sources_group_children = "\n".join(children)
    test_children = []
    for full, rel in test_files:
        test_children.append(f"\t\t\t\t{file_ids[rel]} /* {os.path.basename(full)} */,")
    test_group_children = "\n".join(test_children)
    return f"""/* Begin PBXGroup section */
\t\t{MAIN_GROUP} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{APP_SOURCES_GROUP} /* SourceDesk */,
\t\t\t\t{TEST_SOURCES_GROUP} /* SourceDeskTests */,
\t\t\t\t{PRODUCTS_GROUP} /* Products */,
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{APP_SOURCES_GROUP} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{sources_group_children}
\t\t\t);
\t\t\tpath = SourceDesk;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{TEST_SOURCES_GROUP} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{test_group_children}
\t\t\t);
\t\t\tpath = SourceDeskTests;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{PRODUCTS_GROUP} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{APP_PRODUCT} /* SourceDesk.app */,
\t\t\t\t{TEST_PRODUCT} /* SourceDeskTests.xctest */,
\t\t\t);
\t\t\tname = Products;
\t\t\tsourceTree = "<group>";
\t\t}};
/* End PBXGroup section */"""

def pbx_build_phases():
    return f"""/* Begin PBXSourcesBuildPhase section */
\t\t{SOURCES_PHASE_APP} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{''.join(f'\t\t\t\t{file_ids[rel]} /* {os.path.basename(full)} in Sources */,\n' for full, rel in app_files)}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{SOURCES_PHASE_TEST} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{''.join(f'\t\t\t\t{file_ids[rel]} /* {os.path.basename(full)} in Sources */,\n' for full, rel in test_files)}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXSourcesBuildPhase section */
/* Begin PBXFrameworksBuildPhase section */
\t\t{FRAMEWORKS_PHASE_APP} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{FRAMEWORKS_PHASE_TEST} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXFrameworksBuildPhase section */
/* Begin PBXResourcesBuildPhase section */
\t\t{RESOURCES_PHASE_APP} /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t{ASSET_BUILD} /* Assets.xcassets in Resources */,
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXResourcesBuildPhase section */"""

def pbx_native_targets():
    return f"""/* Begin PBXNativeTarget section */
\t\t{APP_TARGET} /* SourceDesk */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {APP_CONFIG_LIST} /* Build configuration list for PBXNativeTarget "SourceDesk" */;
\t\t\tbuildPhases = (
\t\t\t\t{SOURCES_PHASE_APP} /* Sources */,
\t\t\t\t{FRAMEWORKS_PHASE_APP} /* Frameworks */,
\t\t\t\t{RESOURCES_PHASE_APP} /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = SourceDesk;
\t\t\tproductName = SourceDesk;
\t\t\tproductReference = {APP_PRODUCT} /* SourceDesk.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
\t\t{TEST_TARGET} /* SourceDeskTests */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {TEST_CONFIG_LIST} /* Build configuration list for PBXNativeTarget "SourceDeskTests" */;
\t\t\tbuildPhases = (
\t\t\t\t{SOURCES_PHASE_TEST} /* Sources */,
\t\t\t\t{FRAMEWORKS_PHASE_TEST} /* Frameworks */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t\t{DEP_ID} /* PBXTargetDependency */,
\t\t\t);
\t\t\tname = SourceDeskTests;
\t\t\tproductName = SourceDeskTests;
\t\t\tproductReference = {TEST_PRODUCT} /* SourceDeskTests.xctest */;
\t\t\tproductType = "com.apple.product-type.bundle.unit-test";
\t\t}};
/* End PBXNativeTarget section */"""

def pbx_container_items():
    return f"""/* Begin PBXContainerItemProxy section */
\t\t{PROXY_ID} /* PBXContainerItemProxy */ = {{
\t\t\tisa = PBXContainerItemProxy;
\t\t\tcontainerPortal = {PROJECT_ID} /* Project object */;
\t\t\tproxyType = 1;
\t\t\tremoteGlobalIDString = {APP_TARGET};
\t\t\tremoteInfo = SourceDesk;
\t\t}};
/* End PBXContainerItemProxy section */
/* Begin PBXTargetDependency section */
\t\t{DEP_ID} /* PBXTargetDependency */ = {{
\t\t\tisa = PBXTargetDependency;
\t\t\ttarget = {APP_TARGET} /* SourceDesk */;
\t\t\ttargetProxy = {PROXY_ID} /* PBXContainerItemProxy */;
\t\t}};
/* End PBXTargetDependency section */"""

def pbx_project():
    return f"""/* Begin PBXProject section */
\t\t{PROJECT_ID} /* Project object */ = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 1600;
\t\t\t\tLastUpgradeCheck = 1600;
\t\t\t\tTargetAttributes = {{
\t\t\t\t\t{APP_TARGET} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;
\t\t\t\t\t}};
\t\t\t\t\t{TEST_TARGET} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;
\t\t\t\t\t}};
\t\t\t\t}};
\t\t\t}};
\t\t\tbuildConfigurationList = {PROJ_CONFIG_LIST} /* Build configuration list for PBXProject "SourceDesk" */;
\t\t\tcompatibilityVersion = "Xcode 14.0";
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = {MAIN_GROUP};
\t\t\tproductRefGroup = {PRODUCTS_GROUP} /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t{APP_TARGET} /* SourceDesk */,
\t\t\t\t{TEST_TARGET} /* SourceDeskTests */,
\t\t\t);
\t\t}};
/* End PBXProject section */"""

def config_block(cid, name, overrides, base="Debug"):
    lines = [
        f"\t\t{cid} /* {name} */ = {{",
        "\t\t\tisa = XCBuildConfiguration;",
        f"\t\t\tbuildSettings = {{",
    ]
    for k, v in overrides.items():
        lines.append(f"\t\t\t\t{k} = {v};")
    lines += [
        "\t\t\t};",
        "\t\t\tname = " + name + ";",
        "\t\t};",
    ]
    return "\n".join(lines)

def pbx_configurations():
    app_debug = {
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "1",
        "GENERATE_INFOPLIST_FILE": "YES",
        "INFOPLIST_KEY_CFBundleDisplayName": "SourceDesk",
        "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.productivity",
        "INFOPLIST_KEY_NSHumanReadableCopyright": "",
        "MACOSX_DEPLOYMENT_TARGET": "14.0",
        "MARKETING_VERSION": "1.0",
        "PRODUCT_BUNDLE_IDENTIFIER": "com.sourcedesk.app",
        "PRODUCT_NAME": "$(TARGET_NAME)",
        "SWIFT_EMIT_LOC_STRINGS": "YES",
        "SWIFT_VERSION": "5.0",
        "ENABLE_HARDENED_RUNTIME": "YES",
    }
    app_release = dict(app_debug)
    app_release["SWIFT_COMPILATION_MODE"] = "wholemodule"
    app_debug["ASSETCATALOG_COMPILER_APPICON_NAME"] = "AppIcon"
    app_release["ASSETCATALOG_COMPILER_APPICON_NAME"] = "AppIcon"
    test_debug = {
        "BUNDLE_LOADER": "$(TEST_HOST)",
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "1",
        "GENERATE_INFOPLIST_FILE": "YES",
        "MACOSX_DEPLOYMENT_TARGET": "14.0",
        "MARKETING_VERSION": "1.0",
        "PRODUCT_BUNDLE_IDENTIFIER": "com.sourcedesk.app.tests",
        "PRODUCT_NAME": "$(TARGET_NAME)",
        "SWIFT_VERSION": "5.0",
        "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/SourceDesk.app/Contents/MacOS/SourceDesk",
    }
    test_release = dict(test_debug)
    test_release["SWIFT_COMPILATION_MODE"] = "wholemodule"
    proj_debug = {
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
        "CLANG_ANALYZER_NONNULL": "YES",
        "CLANG_ENABLE_MODULES": "YES",
        "CLANG_ENABLE_OBJC_ARC": "YES",
        "COPY_PHASE_STRIP": "NO",
        "DEBUG_INFORMATION_FORMAT": "dwarf",
        "ENABLE_STRICT_OBJC_MSGSEND": "YES",
        "ENABLE_TESTABILITY": "YES",
        "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
        "GCC_C_LANGUAGE_STANDARD": "gnu17",
        "GCC_DYNAMIC_NO_PIC": "NO",
        "GCC_NO_COMMON_BLOCKS": "YES",
        "GCC_OPTIMIZATION_LEVEL": "0",
        "GCC_PREPROCESSOR_DEFINITIONS": (
            "\"DEBUG=1\", $(inherited),"
        ),
        "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES",
        "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
        "ONLY_ACTIVE_ARCH": "YES",
        "SDKROOT": "macosx",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)",
        "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
    }
    proj_release = {
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
        "CLANG_ANALYZER_NONNULL": "YES",
        "CLANG_ENABLE_MODULES": "YES",
        "CLANG_ENABLE_OBJC_ARC": "YES",
        "COPY_PHASE_STRIP": "NO",
        "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
        "ENABLE_NS_ASSERTIONS": "NO",
        "ENABLE_STRICT_OBJC_MSGSEND": "YES",
        "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
        "GCC_C_LANGUAGE_STANDARD": "gnu17",
        "GCC_NO_COMMON_BLOCKS": "YES",
        "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES",
        "MTL_ENABLE_DEBUG_INFO": "NO",
        "SDKROOT": "macosx",
        "SWIFT_COMPILATION_MODE": "wholemodule",
        "SWIFT_OPTIMIZATION_LEVEL": "-O",
    }
    return f"""/* Begin XCBuildConfiguration section */
{config_block(BUILD_CONFIGS[0], "Debug", app_debug)}
{config_block(BUILD_CONFIGS[1], "Release", app_release)}
{config_block(BUILD_CONFIGS[2], "Debug", test_debug)}
{config_block(BUILD_CONFIGS[3], "Release", test_release)}
{config_block(BUILD_CONFIGS[4], "Debug", proj_debug)}
{config_block(BUILD_CONFIGS[5], "Release", proj_release)}
/* End XCBuildConfiguration section */"""

def pbx_config_lists():
    return f"""/* Begin XCConfigurationList section */
\t\t{APP_CONFIG_LIST} /* Build configuration list for PBXNativeTarget "SourceDesk" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{BUILD_CONFIGS[0]} /* Debug */,
\t\t\t\t{BUILD_CONFIGS[1]} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{TEST_CONFIG_LIST} /* Build configuration list for PBXNativeTarget "SourceDeskTests" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{BUILD_CONFIGS[2]} /* Debug */,
\t\t\t\t{BUILD_CONFIGS[3]} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{PROJ_CONFIG_LIST} /* Build configuration list for PBXProject "SourceDesk" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{BUILD_CONFIGS[4]} /* Debug */,
\t\t\t\t{BUILD_CONFIGS[5]} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
/* End XCConfigurationList section */"""

content = f"""// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 56;
\tobjects = {{
{pbx_file_refs()}

{pbx_groups()}

{pbx_build_phases()}

{pbx_native_targets()}

{pbx_container_items()}

{pbx_project()}

{pbx_configurations()}

{pbx_config_lists()}
\t}};
\trootObject = {PROJECT_ID} /* Project object */;
}}"""

proj_dir = os.path.join(ROOT, "SourceDesk.xcodeproj")
os.makedirs(proj_dir, exist_ok=True)
with open(os.path.join(proj_dir, "project.pbxproj"), "w") as f:
    f.write(content)
print(f"Generated SourceDesk.xcodeproj with {len(app_files)} app files and {len(test_files)} test files")