import { today } from '@/lib/format';
import type { Transaction } from '@/types/phamani';

export type PaymentStatus = 'paid' | 'pending' | 'overdue';

/**
 * Status de pagamento. Compras no cartão não têm status próprio (a dívida está na fatura).
 */
export function paymentStatus(t: Transaction): PaymentStatus | null {
    if (t.account?.type === 'credit') return null;
    if (t.paid_at) return 'paid';

    return t.date.slice(0, 10) < today() ? 'overdue' : 'pending';
}

/**
 * Quem marca como pago é quem pagou:
 * - na sua transação: você, a não ser que o pagador seja um contato que usa o Phamani;
 * - numa cópia compartilhada com você: só se foi você quem pagou.
 */
export function canMarkPaid(t: Transaction): boolean {
    if (t.account?.type === 'credit') return false;
    if (t.mirrored_from_id) return t.paid_by_contact_id == null;

    return !t.paid_by || !t.paid_by.linked_user_id;
}

/** Nome de quem pode marcar (para explicar quando não é você). */
export function payerName(t: Transaction): string | null {
    if (t.mirrored_from_id) {
        return (
            t.mirrored_from?.paid_by?.name ??
            t.mirrored_from?.user?.name ??
            null
        );
    }

    return t.paid_by?.name ?? null;
}
