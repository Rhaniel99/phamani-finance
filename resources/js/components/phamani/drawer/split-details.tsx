import { usePage } from '@inertiajs/react';
import { Users } from 'lucide-react';
import { ContactAvatar } from '@/components/phamani/contact-avatar';
import { useContactAvatar } from '@/hooks/use-contacts';
import { formatCurrency } from '@/lib/format';
import { cn } from '@/lib/utils';
import { SHARE_STATUS_LABELS } from '@/types/phamani';
import type { ShareStatus, Transaction } from '@/types/phamani';

const STATUS_STYLES: Record<ShareStatus, string> = {
    pending: 'bg-[#E8DCC4] text-[#6B4E3D]',
    accepted: 'bg-[#E3F9E5] text-[#1F5428]',
    declined: 'bg-[#FCE7E7] text-[#A65D57]',
    left: 'bg-[#FCE7E7] text-[#A65D57]',
    removed: 'bg-[#E8DCC4] text-[#8B7355]',
};

/**
 * Bloco "Divisão" do drawer.
 * - Transação sua: mostra as partes e o status de quem é usuário do Phamani (aceitou, aguardando…).
 * - Cópia compartilhada com você: mostra a divisão original, com "Você" no lugar do seu nome.
 */
export function SplitDetails({ transaction }: { transaction: Transaction }) {
    const authUser = usePage().props.auth.user;
    const me = authUser?.id;
    const contactAvatar = useContactAvatar();
    const source = transaction.mirrored_from;
    const isMirror = !!transaction.mirrored_from_id && !!source;

    const splits = isMirror
        ? (source.splits ?? [])
        : (transaction.splits ?? []);
    if (splits.length === 0) return null;

    const ownerName = isMirror ? (source.user?.name ?? 'Quem criou') : 'Você';
    const total = isMirror ? source.total_amount : transaction.total_amount;

    const labelOf = (s: (typeof splits)[number]) => {
        if (s.contact_id === null) return ownerName;
        if (
            isMirror &&
            s.contact &&
            'linked_user_id' in s.contact &&
            s.contact.linked_user_id === me
        )
            return 'Você';
        return s.contact?.name ?? '—';
    };

    const avatarOf = (s: (typeof splits)[number]): string | null => {
        if (isMirror) {
            if (s.contact_id === null) return source.user?.avatar ?? null;
            if (
                s.contact &&
                'linked_user_id' in s.contact &&
                s.contact.linked_user_id === me
            )
                return authUser?.avatar ?? null;
            return null;
        }
        return s.contact_id === null
            ? (authUser?.avatar ?? null)
            : contactAvatar(s.contact_id);
    };

    let payer: string;
    if (isMirror) {
        payer = !source.paid_by
            ? ownerName
            : source.paid_by.linked_user_id === me
              ? 'você'
              : source.paid_by.name;
    } else {
        payer = transaction.paid_by?.name ?? 'você';
    }

    const statusOf = (contactId: string | null): ShareStatus | null => {
        if (isMirror || !contactId) return null;
        const link = transaction.share_links?.find(
            (l) => l.share?.owner_contact_id === contactId,
        );
        return link?.share?.status ?? null;
    };

    // Dono primeiro
    const ordered = [...splits].sort(
        (a, b) => Number(a.contact_id !== null) - Number(b.contact_id !== null),
    );

    return (
        <div className="rounded-3xl border border-[#D4C5A9] bg-white p-6">
            <div className="mb-4 flex items-center justify-between">
                <h4 className="flex items-center gap-2 font-bold text-[#3D2817]">
                    <Users className="h-4 w-4" />
                    Divisão
                </h4>
                <span className="text-xs text-[#8B7355]">
                    Pago por <strong>{payer}</strong>
                </span>
            </div>
            <ul className="space-y-2">
                {ordered.map((s) => {
                    const status = statusOf(s.contact_id);
                    return (
                        <li
                            key={s.id}
                            className="flex items-center justify-between gap-2 text-sm"
                        >
                            <span className="flex items-center gap-2 text-[#3D2817]">
                                <ContactAvatar
                                    name={labelOf(s)}
                                    avatar={avatarOf(s)}
                                    className="h-6 w-6 text-[10px]"
                                />
                                {labelOf(s)}
                                {status && (
                                    <span
                                        className={cn(
                                            'rounded-md px-1.5 py-0.5 text-[10px] font-bold uppercase',
                                            STATUS_STYLES[status],
                                        )}
                                    >
                                        {SHARE_STATUS_LABELS[status]}
                                    </span>
                                )}
                            </span>
                            <span className="font-bold text-[#3D2817]">
                                {formatCurrency(s.amount)}
                            </span>
                        </li>
                    );
                })}
            </ul>
            <div className="mt-3 flex items-center justify-between border-t border-[#E8DCC4] pt-3 text-sm">
                <span className="text-[#8B7355]">Total</span>
                <span className="font-bold text-[#3D2817]">
                    {formatCurrency(total)}
                </span>
            </div>
        </div>
    );
}
