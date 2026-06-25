<script>
    import { locale, availableLocales } from "$lib/i18n";

    function handleChange(e) {
        locale.set(e.target.value);
    }
</script>

<div class="lang-switcher">
    <select class="lang-select" value={$locale} on:change={handleChange}>
        {#each availableLocales as lang}
            <option value={lang.code}>{lang.flag} {lang.label}</option>
        {/each}
    </select>
</div>

<style>
    .lang-switcher {
        display: inline-flex;
        align-items: center;
    }
    
    .lang-select {
        appearance: none;
        background: transparent;
        border: 1px solid var(--border, #e2e8f0);
        border-radius: var(--radius-sm, 6px);
        padding: 6px 32px 6px 12px;
        font-size: 0.875rem;
        font-weight: 500;
        color: var(--text, #1e293b);
        cursor: pointer;
        outline: none;
        /* Custom dropdown arrow */
        background-image: url("data:image/svg+xml;charset=US-ASCII,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22292.4%22%20height%3D%22292.4%22%3E%3Cpath%20fill%3D%22%23475569%22%20d%3D%22M287%2069.4a17.6%2017.6%200%200%200-13-5.4H18.4c-5%200-9.3%201.8-12.9%205.4A17.6%2017.6%200%200%200%200%2082.2c0%205%201.8%209.3%205.4%2012.9l128%20127.9c3.6%203.6%207.8%205.4%2012.8%205.4s9.2-1.8%2012.8-5.4L287%2095c3.5-3.5%205.4-7.8%205.4-12.8%200-5-1.9-9.2-5.5-12.8z%22%2F%3E%3C%2Fsvg%3E");
        background-repeat: no-repeat, repeat;
        background-position: right 10px top 50%, 0 0;
        background-size: 10px auto, 100%;
        transition: border-color 0.2s;
    }

    .lang-select:hover {
        border-color: var(--primary, #3b82f6);
    }
    
    .lang-select:focus {
        border-color: var(--primary, #3b82f6);
        box-shadow: 0 0 0 3px rgba(59, 130, 246, 0.1);
    }
</style>
