import { writable, derived } from 'svelte/store';
import es from './es.json';
import ht from './ht.json';

const dictionaries = {
    es,
    ht
};

const defaultLocale = 'es';

// All supported locales with display metadata
export const availableLocales = [
    { code: 'es', label: 'Español',  flag: '🇪🇸' },
    { code: 'ht', label: 'Kreyòl',   flag: '🇭🇹' },
];

// Check if window is defined to safely access localStorage (SSR support)
const initialLocale = typeof window !== 'undefined'
    ? (localStorage.getItem('locale') || defaultLocale)
    : defaultLocale;

export const locale = writable(initialLocale);

// When locale changes, update localStorage so preference is persisted
if (typeof window !== 'undefined') {
    locale.subscribe((value) => {
        if (dictionaries[value]) {
            localStorage.setItem('locale', value);
        }
    });
}

// Function to safely lookup nested keys, e.g. "auth.login"
function getNestedValue(obj, path) {
    return path.split('.').reduce((acc, part) => acc && acc[part], obj);
}

// Derived store to translate text based on the current locale
export const t = derived(locale, ($locale) => (key, vars = {}) => {
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
