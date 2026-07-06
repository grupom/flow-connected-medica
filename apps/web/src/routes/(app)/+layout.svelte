<script>
    import { onMount } from "svelte";
    import { goto } from "$app/navigation";
    import { page } from "$app/stores";
    import { auth } from "$lib/auth.js";
    import { api, refreshSession } from "$lib/api.js";
    import { systemSettings } from "$lib/stores.js";
    import { locale } from "$lib/i18n";
    import Sidebar from "$lib/components/Sidebar.svelte";
    import Topbar from "$lib/components/Topbar.svelte";

    const PAGE_TITLES = {
        "/dashboard": "Dashboard",
        "/admin/users": "Users",
        "/admin/roles": "Roles",
        "/admin/modules": "Modules",
        "/admin/stations": "Stations",
        "/admin/boards": "Display Boards",
        "/admin/settings": "Settings",
        "/station": "Station Operations",
    };

    $: title = PAGE_TITLES[$page.url.pathname] ?? "Flow Connected";

    $: if ($auth.accessToken && $auth.user) {
        const roles = $auth.user.role_codes || [];
        const isDesk = roles.includes("DESK") && !roles.includes("ADMIN");
        
        if (isDesk && ($page.url.pathname === "/dashboard" || $page.url.pathname === "/")) {
            goto("/front-desk");
        }
    }

    async function loadSystemSettings() {
        try {
            const res = await api.get("/api/admin/settings");
            systemSettings.set(res.data);
            // If multi-language is disabled, force Spanish
            if (!res.data.multi_language) {
                locale.set("es");
            }
        } catch {
            // Non-critical — keep defaults
        }
    }

    onMount(async () => {
        // Try to rehydrate session from stored refresh token. Goes through
        // the shared refreshSession() (same mutex apiFetch uses) instead of
        // calling the endpoint directly, so a page reload can't race a
        // concurrent refresh from another in-flight request in this tab.
        if (!$auth.accessToken) {
            const rt = auth.getRefreshToken();
            if (rt) {
                try {
                    await refreshSession();
                } catch {
                    auth.logout();
                    goto("/login");
                }
            } else {
                auth.markReady();
                goto("/login");
            }
        }
        await loadSystemSettings();
    });

    $: if ($auth.ready && !$auth.accessToken) {
        goto("/login");
    }
</script>

{#if $auth.accessToken}
    <div class="app-shell">
        <Sidebar />
        <main class="main-content">
            <Topbar {title} />
            <div class="page-body fade-in">
                <slot />
            </div>
        </main>
    </div>
{:else}
    <div class="app-loading">
        <div class="spinner" />
        <p>Loading…</p>
    </div>
{/if}

<style>
    .app-loading {
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        height: 100vh;
        gap: 16px;
        color: var(--text-muted);
    }
    .spinner {
        width: 36px;
        height: 36px;
        border: 3px solid var(--border);
        border-top-color: var(--primary);
        border-radius: 50%;
        animation: spin 0.7s linear infinite;
    }
    @keyframes spin {
        to {
            transform: rotate(360deg);
        }
    }
</style>
