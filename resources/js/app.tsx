import { createInertiaApp } from '@inertiajs/react';
import PhamaniLayout from '@/layouts/phamani-layout';

const appName = import.meta.env.VITE_APP_NAME || 'Phamani';

void createInertiaApp({
    title: (title) => (title ? `${title} - ${appName}` : appName),
    layout: () => PhamaniLayout,
    strictMode: true,
    progress: {
        color: '#6B4F3A',
    },
});
