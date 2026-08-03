import { writable, derived } from 'svelte/store';
import es from './es.json';
import ht from './ht.json';
import en from './en.json';

const dictionaries = {
    es,
    ht,
    en
};

const defaultLocale = 'es';

// All supported locales with display metadata
export const availableLocales = [
    { code: 'es', label: 'Español',  flag: '🇪🇸' },
    { code: 'ht', label: 'Kreyòl',   flag: '🇭🇹' },
    { code: 'en', label: 'English',  flag: '🇺🇸' },
];

// Function to safely lookup nested keys, e.g. "auth.login"
function getNestedValue(obj, path) {
    return path.split('.').reduce((acc, part) => acc && acc[part], obj);
}

// Builds an independent { locale, t } pair persisted under its own
// localStorage key. Used to keep the patient-facing locale (login, kiosk,
// board — gated by the `multi_language` system setting) separate from the
// staff dashboard's own language preference, which staff can always change
// regardless of what's configured for patient-facing screens.
function createLocaleStore(storageKey) {
    const initialLocale = typeof window !== 'undefined'
        ? (localStorage.getItem(storageKey) || defaultLocale)
        : defaultLocale;

    const localeStore = writable(initialLocale);

    if (typeof window !== 'undefined') {
        localeStore.subscribe((value) => {
            if (dictionaries[value]) {
                localStorage.setItem(storageKey, value);
            }
        });
    }

    const tStore = derived(localeStore, ($locale) => (key, vars = {}) => {
        const dict = dictionaries[$locale] || dictionaries[defaultLocale];
        let text = getNestedValue(dict, key);

        // Fallback if translation is missing in the current locale
        if (!text && $locale !== defaultLocale) {
            text = getNestedValue(dictionaries[defaultLocale], key);
        }

        // Fallback if missing entirely
        if (!text) return key;

        // Optional: support variables in translations, e.g. "Hello {{name}}"
        Object.keys(vars).forEach((k) => {
            const regex = new RegExp(`{{${k}}}`, 'g');
            text = text.replace(regex, vars[k]);
        });

        return text;
    });

    return { locale: localeStore, t: tStore };
}

// Patient-facing locale — login, kiosk, board. Gated by the `multi_language`
// system setting (see admin/settings/language).
export const { locale, t } = createLocaleStore('locale');

// Staff dashboard locale — Sidebar, page titles, admin/* screens. Independent
// of `multi_language`, which only concerns patient-facing screens.
export const { locale: adminLocale, t: adminT } = createLocaleStore('admin_locale');
