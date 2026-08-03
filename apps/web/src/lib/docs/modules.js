// Shared source of truth for the /docs section: drives the left nav, the
// per-module placeholder page (routes/docs/[slug]/+page.svelte), and the
// "En esta página" right rail (each section becomes an anchor).
// Real content goes into each module's `sections` progressively — the
// structure itself doesn't need to change to add prose later.
export const docsModules = [
    {
        slug: '',
        title: 'Introducción',
        icon: '📖',
        sections: [
            { id: 'que-es', title: 'Qué es Flow Connected' },
            { id: 'modulos', title: 'Módulos de la aplicación' },
            { id: 'como-usar', title: 'Cómo usar esta guía' },
        ],
    },
    {
        slug: 'panel',
        title: 'Panel',
        icon: '📊',
        sections: [
            { id: 'resumen', title: 'Resumen del panel' },
            { id: 'metricas', title: 'Métricas principales' },
        ],
    },
    {
        slug: 'recepcion',
        title: 'Recepción',
        icon: '⚡',
        sections: [
            { id: 'crear-turno', title: 'Crear un turno' },
            { id: 'planes-visita', title: 'Planes de visita multi-cola' },
        ],
    },
    {
        slug: 'ventanilla',
        title: 'Ventanilla',
        icon: '🎫',
        sections: [
            { id: 'llamar-turno', title: 'Llamar el siguiente turno' },
            { id: 'atender-finalizar', title: 'Atender y finalizar' },
            { id: 'no-show-transferencias', title: 'No-show y transferencias' },
        ],
    },
    {
        slug: 'pantallas-kiosco',
        title: 'Pantallas y Kiosco',
        icon: '📺',
        sections: [
            { id: 'tableros', title: 'Tableros de pantalla' },
            { id: 'kiosco', title: 'Kiosco de autoservicio' },
        ],
    },
    {
        slug: 'reportes',
        title: 'Reportes',
        icon: '📉',
        sections: [
            { id: 'tickets', title: 'Reporte de turnos' },
            { id: 'tiempos-espera', title: 'Tiempos de espera' },
            { id: 'demanda', title: 'Congestión y demanda' },
        ],
    },
    {
        slug: 'administracion',
        title: 'Administración',
        icon: '⚙️',
        sections: [
            { id: 'usuarios-roles', title: 'Usuarios y roles' },
            { id: 'estaciones-modulos', title: 'Estaciones y módulos' },
            { id: 'configuracion', title: 'Configuración general' },
        ],
    },
    {
        slug: 'mi-perfil',
        title: 'Mi Perfil',
        icon: '👤',
        sections: [
            { id: 'datos-personales', title: 'Datos personales' },
            { id: 'cambiar-password', title: 'Cambiar contraseña' },
        ],
    },
];

export function findDocModule(slug) {
    return docsModules.find((m) => m.slug === (slug || ''));
}
