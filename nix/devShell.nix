pkgs:
let
  androidPlatform = "34";
  androidBuildTools = "34.0.0";
  androidNdk = "27.0.12077973";

  androidAbi = if pkgs.stdenv.hostPlatform.isAarch64 then "arm64-v8a" else "x86_64";
  androidJdk = pkgs.jdk17_headless;
  androidSdk = pkgs.androidenv.composeAndroidPackages {
    platformVersions = [ androidPlatform ];
    buildToolsVersions = [ androidBuildTools ];
    toolsVersion = null;
    includeNDK = true;
    ndkVersions = [ androidNdk ];
    includeEmulator = true;
    includeSystemImages = true;
    systemImageTypes = [ "google_apis" ];
    abiVersions = [ androidAbi ];
    includeSources = false;
    includeCmake = false;
  };
in
rec {
  packages =
    with pkgs;
    [
      pkg-config

      rustToolchain
      mold
      cargo-binstall

      androidSdk.androidsdk
      androidJdk

      just
      just-lsp
    ]
    ++ lib.optionals stdenv.hostPlatform.isLinux [
      openssl
      glib
      gtk3
      webkitgtk_4_1
      xdotool
    ];

  env = with pkgs; rec {
    LD_LIBRARY_PATH = lib.makeLibraryPath packages;
    RUST_SRC_PATH = "${rustToolchain}/lib/rustlib/src/rust/library";
    ANDROID_HOME = "${androidSdk.androidsdk}/libexec/android-sdk";
    ANDROID_NDK_ROOT = "${ANDROID_HOME}/ndk/${androidNdk}";
    ANDROID_NDK_HOME = ANDROID_NDK_ROOT;
    NDK_HOME = ANDROID_NDK_ROOT;
    JAVA_HOME = "${androidJdk}/lib/openjdk";
  };

  shellHook = ''
    export CARGO_HOME="$PWD/.cargo"
    export PATH="$CARGO_HOME/bin:$PWD/target/debug:$PATH"
    export GRADLE_OPTS="''${GRADLE_OPTS:+$GRADLE_OPTS }-Dorg.gradle.project.android.aapt2FromMavenOverride=$ANDROID_HOME/build-tools/${androidBuildTools}/aapt2"
  '';
}
