<script context="module">
    /** @type {import('@sveltejs/kit').Load} */
    export async function load({ url, params }) {
        return {
            props: {
                params,
                path: url.pathname,
            }
        };
    }
</script>
<script lang="ts">
    import '../app.css';

    import { onMount } from 'svelte';
    import { webVitals } from '$lib/webvitals';

    export let path: string;
    export let params: Record<string, string>;

    onMount(() => {
        webVitals({ path, params });
    });
</script>

<slot></slot>
