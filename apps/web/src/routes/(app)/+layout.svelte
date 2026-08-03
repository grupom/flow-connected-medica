<script>
    import { onMount } from "svelte";
    import { goto } from "$app/navigation";
    import { page } from "$app/stores";
    import { auth } from "$lib/auth.js";
    import { api, refreshSession } from "$lib/api.js";
    import { systemSettings } from "$lib/stores.js";
    import { locale, adminLocale, adminT as t } from "$lib/i18n";
    import Sidebar from "$lib/components/Sidebar.svelte";
    import Topbar from "$lib/components/Topbar.svelte";

    $: PAGE_TITLES = {
        "/dashboard": $t("page_titles.dashboard"),
        "/admin/users": $t("page_titles.users"),
        "/admin/roles": $t("page_titles.roles"),
        "/admin/modules": $t("page_titles.modules"),
        "/admin/stations": $t("page_titles.stations"),
        "/admin/boards": $t("page_titles.display_boards"),
        "/admin/settings": $t("page_titles.settings"),
        "/station": $t("page_titles.station_ops"),
    };

    $: title = PAGE_TITLES[$page.url.pathname] ?? $t("page_titles.default");

    $: if ($auth.user) {
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
            // If multi-language is disabled, force Spanish everywhere —
            // patient-facing screens and the staff dashboard alike.
            if (!res.data.multi_language) {
                locale.set("es");
                adminLocale.set("es");
            }
        } catch {
            // Non-critical — keep defaults
        }
    }

    onMount(async () => {
        // Always attempt a silent refresh — there's no client-readable token
        // to check first anymore (the refresh token lives in an httpOnly
        // cookie). Goes through the shared refreshSession() (same mutex
        // apiFetch uses) instead of calling the endpoint directly, so a page
        // reload can't race a concurrent refresh from another in-flight
        // request in this tab. The server's cookie (or lack of one) decides.
        try {
            await refreshSession();
        } catch {
            auth.logout();
            goto("/login");
            return;
        }
        await loadSystemSettings();
    });

    $: if ($auth.ready && !$auth.user) {
        goto("/login");
    }
</script>

{#if $auth.user}
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
