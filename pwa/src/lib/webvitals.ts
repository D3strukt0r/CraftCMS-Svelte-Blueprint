import type { Metric } from 'web-vitals';
import { getCLS, getFCP, getFID, getLCP, getTTFB } from 'web-vitals';

type AnalyticsOptions = {
    params: Record<string, string>;
    path: string;
    // analyticsId: string;
    debug?: true;
};
//
// // const vitalsUrl = 'https://vitals.vercel-analytics.com/v1/vitals';
// const vitalsUrl = '/vitals';
//
// function getConnectionSpeed(): string {
//     return 'connection' in navigator &&
//            navigator['connection'] &&
//            'effectiveType' in navigator['connection']
//            ? navigator['connection']['effectiveType']
//            : '';
// }
//
function sendToAnalytics(metric: Metric, options: AnalyticsOptions) {
    console.log(metric);
    return;
//
//     // Extract the route from the 'page' and 'params' options
//     const page = Object.entries(options.params).reduce(
//         (acc, [key, value]) => acc.replace(value, `[${key}]`),
//         options.path
//     );
//
//     const body = {
//         // dsn: options.analyticsId,
//         id: metric.id,
//         page,
//         href: location.href,
//         event_name: metric.name,
//         value: metric.value.toString(),
//         speed: getConnectionSpeed()
//     };
//
//     if (options.debug) {
//         console.log('[Analytics]', metric.name, JSON.stringify(body, null, 2));
//     }
//
//     const blob = new Blob([new URLSearchParams(body).toString()], {
//         // This content type is necessary for `sendBeacon`:
//         type: 'application/x-www-form-urlencoded'
//     });
//     if (navigator.sendBeacon) {
//         navigator.sendBeacon(vitalsUrl, blob);
//     } else {
//         fetch(vitalsUrl, {
//             body: blob,
//             method: 'POST',
//             credentials: 'omit',
//             keepalive: true
//         });
//     }
}

export function webVitals(options: AnalyticsOptions): void {
    try {
        getFID((metric) => sendToAnalytics(metric, options));
        getTTFB((metric) => sendToAnalytics(metric, options));
        getLCP((metric) => sendToAnalytics(metric, options));
        getCLS((metric) => sendToAnalytics(metric, options));
        getFCP((metric) => sendToAnalytics(metric, options));
    } catch (err) {
        console.error('[Analytics]', err);
    }
}
