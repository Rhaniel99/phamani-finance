import { router, usePage } from '@inertiajs/react';
import { logout as logoutRoute } from '@/routes';

export function useAuth() {
    const { user } = usePage().props.auth;

    const logout = () => {
        router.flushAll();
        router.post(logoutRoute.url());
    };

    return {
        user,
        logout,
        isLoggedIn: Boolean(user),
        avatarUrl: user?.avatar ?? null,
        name: user?.name ?? null,
    };
}
