import { Link, router, usePage, usePoll } from '@inertiajs/react';
import { Bell } from 'lucide-react';
import {
    DropdownMenu,
    DropdownMenuContent,
    DropdownMenuItem,
    DropdownMenuLabel,
    DropdownMenuSeparator,
    DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { inbox } from '@/routes';
import { read as markRead } from '@/routes/notifications';
import type { NotificationsProp } from '@/types/phamani';

/**
 * Sino de notificações.
 *
 * Hoje: recarrega só a prop "notifications" a cada 60s (usePoll).
 * Com Reverb: troque o usePoll por um listener do Echo no canal privado do usuário
 * que chama router.reload({ only: ['notifications'] }) — o componente continua igual.
 */
export function NotificationsBell() {
    const notifications = usePage().props.notifications as
        | NotificationsProp
        | null
        | undefined;

    usePoll(60_000, { only: ['notifications'] });

    if (!notifications) return null;

    const badge = notifications.unread + notifications.pending;

    function onOpenChange(open: boolean) {
        if (open && notifications!.unread > 0) {
            router.post(
                markRead.url(),
                {},
                {
                    preserveState: true,
                    preserveScroll: true,
                    only: ['notifications'],
                },
            );
        }
    }

    return (
        <DropdownMenu onOpenChange={onOpenChange}>
            <DropdownMenuTrigger asChild>
                <button
                    type="button"
                    aria-label={`Notificações${badge ? ` (${badge})` : ''}`}
                    className="relative flex h-12 w-12 items-center justify-center rounded-full border-2 border-[#E8DCC4] bg-[#FBF7F1] text-[#6B4F3A] transition-colors hover:bg-[#E8DCC4]"
                >
                    <Bell className="h-5 w-5" />
                    {badge > 0 && (
                        <span className="absolute -top-1 -right-1 flex h-5 min-w-5 items-center justify-center rounded-full bg-[#A65D57] px-1 text-[10px] font-bold text-white">
                            {badge > 9 ? '9+' : badge}
                        </span>
                    )}
                </button>
            </DropdownMenuTrigger>

            <DropdownMenuContent align="end" className="w-80 rounded-xl">
                <DropdownMenuLabel className="flex items-center justify-between">
                    <span className="text-sm font-semibold text-[#3D2817]">
                        Notificações
                    </span>
                    {notifications.pending > 0 && (
                        <span className="rounded-md bg-[#FCE7E7] px-2 py-0.5 text-[10px] font-bold text-[#A65D57] uppercase">
                            {notifications.pending} pendente
                            {notifications.pending > 1 ? 's' : ''}
                        </span>
                    )}
                </DropdownMenuLabel>
                <DropdownMenuSeparator />

                {notifications.latest.length === 0 && (
                    <p className="px-3 py-6 text-center text-sm text-[#8B7355]">
                        Nada por aqui.
                    </p>
                )}

                <div className="max-h-80 overflow-y-auto">
                    {notifications.latest.map((n) => (
                        <DropdownMenuItem
                            key={n.id}
                            asChild
                            className="cursor-pointer"
                        >
                            <Link
                                href={n.data.url ?? inbox.url()}
                                className="flex flex-col items-start gap-0.5 px-3 py-2"
                            >
                                <span className="flex items-center gap-2 text-sm font-semibold text-[#3D2817]">
                                    {!n.read_at && (
                                        <span className="h-2 w-2 rounded-full bg-[#A65D57]" />
                                    )}
                                    {n.data.title}
                                </span>
                                <span className="text-xs text-[#6B4E3D]">
                                    {n.data.body}
                                </span>
                                <span className="text-[10px] text-[#8B7355]">
                                    {new Date(n.created_at).toLocaleString(
                                        'pt-BR',
                                        {
                                            day: '2-digit',
                                            month: '2-digit',
                                            hour: '2-digit',
                                            minute: '2-digit',
                                        },
                                    )}
                                </span>
                            </Link>
                        </DropdownMenuItem>
                    ))}
                </div>

                <DropdownMenuSeparator />
                <DropdownMenuItem asChild className="cursor-pointer">
                    <Link
                        href={inbox.url()}
                        className="justify-center text-sm font-medium text-[#6B4F3A]"
                    >
                        Ver pendências
                    </Link>
                </DropdownMenuItem>
            </DropdownMenuContent>
        </DropdownMenu>
    );
}
