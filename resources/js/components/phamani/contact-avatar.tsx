import { UserRound } from 'lucide-react';
import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar';
import { cn } from '@/lib/utils';

interface ContactAvatarProps {
    name: string;
    /** Foto do Google quando a pessoa usa o Phamani (contato vinculado). */
    avatar?: string | null;
    className?: string;
}

function initials(name: string): string {
    const words = name
        .replace(/@.*/, '')
        .split(/[\s._-]+/)
        .filter(Boolean);

    return (
        (words[0]?.[0] ?? '') +
        (words.length > 1 ? (words.at(-1)?.[0] ?? '') : '')
    ).toUpperCase();
}

/**
 * Avatar de uma pessoa: foto quando vinculada a uma conta do Phamani,
 * iniciais (ou ícone genérico) quando é só um contato.
 */
export function ContactAvatar({ name, avatar, className }: ContactAvatarProps) {
    const text = initials(name);

    return (
        <Avatar className={cn('h-8 w-8', className)}>
            {avatar && (
                <AvatarImage
                    src={avatar}
                    alt={name}
                    // Fotos do Google podem falhar com Referer de outro domínio.
                    referrerPolicy="no-referrer"
                />
            )}
            <AvatarFallback className="bg-[#E8DCC4] text-[0.65em] font-bold text-[#6B4E3D]">
                {text || <UserRound className="h-1/2 w-1/2" />}
            </AvatarFallback>
        </Avatar>
    );
}
