import { Link } from '@inertiajs/react';
import { ArrowLeft, Hash, Inbox, LogOut, Users, Wallet } from 'lucide-react';
import { useState } from 'react';
import type { ReactNode } from 'react';
import { ContactsModal } from '@/components/phamani/modal/contacts-modal';
import { TagsModal } from '@/components/phamani/modal/tags-modal';
import { NotificationsBell } from '@/components/phamani/notifications-bell';
import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar';
import {
    DropdownMenu,
    DropdownMenuContent,
    DropdownMenuItem,
    DropdownMenuLabel,
    DropdownMenuSeparator,
    DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { useAuth } from '@/hooks/use-auth';
import { inbox } from '@/routes';

interface DashboardHeaderProps {
    title: string;
    subtitle?: string;
    onBack?: () => void;
    actions?: ReactNode;
}

export function DashboardHeader({
    title,
    subtitle,
    onBack,
    actions,
}: DashboardHeaderProps) {
    const { user, avatarUrl, name, logout } = useAuth();
    const [contactsOpen, setContactsOpen] = useState(false);
    const [tagsOpen, setTagsOpen] = useState(false);

    return (
        <header className="mb-10 flex items-center justify-between gap-4">
            <div className="flex items-center gap-4">
                {onBack && (
                    <button
                        type="button"
                        onClick={onBack}
                        aria-label="Voltar"
                        className="-ml-2 rounded-xl border-2 border-transparent p-2 text-[#6B4F3A] transition-colors hover:border-[#E8DCC4] hover:bg-[#E8DCC4]"
                    >
                        <ArrowLeft className="h-6 w-6" />
                    </button>
                )}

                <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-[#6B4F3A] text-[#F5EFE6] shadow-lg">
                    <Wallet className="h-6 w-6" />
                </div>

                <div>
                    <h1 className="text-2xl font-bold text-[#3D2817]">
                        {title}
                    </h1>
                    {subtitle && (
                        <p className="text-sm text-[#8B7355]">{subtitle}</p>
                    )}
                </div>
            </div>

            <div className="flex items-center gap-4">
                {actions}

                <NotificationsBell />

                <DropdownMenu>
                    <DropdownMenuTrigger asChild>
                        <button
                            type="button"
                            aria-label="Menu do usuário"
                            className="rounded-full"
                        >
                            <Avatar className="h-12 w-12 border-2 border-[#E8DCC4]">
                                <AvatarImage
                                    src={avatarUrl ?? undefined}
                                    alt={name ?? ''}
                                    referrerPolicy="no-referrer"
                                />
                                <AvatarFallback className="bg-[#E8DCC4] font-bold text-[#6B4F3A]">
                                    {name?.charAt(0).toUpperCase() ?? 'U'}
                                </AvatarFallback>
                            </Avatar>
                        </button>
                    </DropdownMenuTrigger>

                    <DropdownMenuContent
                        align="end"
                        className="w-56 rounded-xl"
                    >
                        <DropdownMenuLabel className="font-normal">
                            <p className="text-sm font-semibold text-[#3D2817]">
                                {user?.name}
                            </p>
                            <p className="truncate text-xs text-[#8B7355]">
                                {user?.email}
                            </p>
                        </DropdownMenuLabel>
                        <DropdownMenuSeparator />
                        <DropdownMenuItem asChild className="cursor-pointer">
                            <Link href={inbox.url()}>
                                <Inbox className="mr-2" />
                                Pendências
                            </Link>
                        </DropdownMenuItem>
                        <DropdownMenuItem
                            onSelect={() => setContactsOpen(true)}
                            className="cursor-pointer"
                        >
                            <Users className="mr-2" />
                            Contatos
                        </DropdownMenuItem>
                        <DropdownMenuItem
                            onSelect={() => setTagsOpen(true)}
                            className="cursor-pointer"
                        >
                            <Hash className="mr-2" />
                            Tags
                        </DropdownMenuItem>
                        <DropdownMenuItem
                            onSelect={logout}
                            className="cursor-pointer"
                        >
                            <LogOut className="mr-2" />
                            Sair
                        </DropdownMenuItem>
                    </DropdownMenuContent>
                </DropdownMenu>
            </div>
            <ContactsModal open={contactsOpen} onOpenChange={setContactsOpen} />
            <TagsModal open={tagsOpen} onOpenChange={setTagsOpen} />
        </header>
    );
}
