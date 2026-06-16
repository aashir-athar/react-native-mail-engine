/**
 * Expo Config Plugin for `react-native-mail-engine`.
 *
 * The package is a Nitro module, so bare React Native consumers autolink it
 * without any plugin. This plugin is for **Expo (prebuild)** consumers — it
 * writes the small amount of native config a mail engine needs:
 *
 *   - **Android**: ensures `INTERNET` (and, by default, `ACCESS_NETWORK_STATE`).
 *   - **iOS**: optionally adds the `fetch` background mode (`iosBackgroundFetch`)
 *     for background refresh, and — for local development only — an App Transport
 *     Security exception (`allowInsecureNetwork`) so you can talk to a plaintext
 *     dev mail server. Android cleartext is gated behind the same flag.
 *
 * Usage in `app.json` / `app.config.ts`:
 *
 *   ["react-native-mail-engine", {
 *     "iosBackgroundFetch": false,
 *     "allowInsecureNetwork": false,
 *     "androidNetworkStatePermission": true
 *   }]
 */

import {
  AndroidConfig,
  type ConfigPlugin,
  createRunOncePlugin,
  withAndroidManifest,
  withInfoPlist,
} from '@expo/config-plugins';

const pkg = require('../../package.json') as { name: string; version: string };

export interface PluginOptions {
  /** Add the iOS `fetch` background mode. Defaults to `false`. */
  iosBackgroundFetch?: boolean;
  /**
   * Allow cleartext (non-TLS) connections — iOS ATS `NSAllowsArbitraryLoads` and
   * Android `usesCleartextTraffic`. **Development only.** Defaults to `false`.
   */
  allowInsecureNetwork?: boolean;
  /** Inject `ACCESS_NETWORK_STATE` on Android. Defaults to `true`. */
  androidNetworkStatePermission?: boolean;
}

// ---------------------------------------------------------------------------
// iOS
// ---------------------------------------------------------------------------

const withIos: ConfigPlugin<PluginOptions> = (config, opts) =>
  withInfoPlist(config, (cfg) => {
    const plist = cfg.modResults as Record<string, unknown>;

    if (opts.iosBackgroundFetch) {
      const modes = new Set<string>(
        Array.isArray(plist.UIBackgroundModes) ? (plist.UIBackgroundModes as string[]) : []
      );
      modes.add('fetch');
      plist.UIBackgroundModes = Array.from(modes);
    }

    if (opts.allowInsecureNetwork) {
      const ats = (plist.NSAppTransportSecurity as Record<string, unknown> | undefined) ?? {};
      ats.NSAllowsArbitraryLoads = true;
      plist.NSAppTransportSecurity = ats;
    }

    return cfg;
  });

// ---------------------------------------------------------------------------
// Android
// ---------------------------------------------------------------------------

const withAndroid: ConfigPlugin<PluginOptions> = (config, opts) =>
  withAndroidManifest(config, (cfg) => {
    const manifest = cfg.modResults;

    AndroidConfig.Permissions.ensurePermission(manifest, 'android.permission.INTERNET');
    if (opts.androidNetworkStatePermission !== false) {
      AndroidConfig.Permissions.ensurePermission(
        manifest,
        'android.permission.ACCESS_NETWORK_STATE'
      );
    }

    if (opts.allowInsecureNetwork) {
      const application = AndroidConfig.Manifest.getMainApplicationOrThrow(manifest);
      // The manifest attribute bag is loosely typed XML JSON — set pragmatically.
      (application.$ as Record<string, string>)['android:usesCleartextTraffic'] = 'true';
    }

    return cfg;
  });

// ---------------------------------------------------------------------------

const withMailEngine: ConfigPlugin<PluginOptions | void> = (config, options) => {
  const opts = options ?? {};
  config = withIos(config, opts);
  config = withAndroid(config, opts);
  return config;
};

export default createRunOncePlugin(withMailEngine, pkg.name, pkg.version);
