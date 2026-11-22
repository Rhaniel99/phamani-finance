import { today } from '@/lib/format';
import type { Transaction } from '@/types/phamani';

export type PaymentStatus = 'paid' | 'pending' | 'overdue' | 'invoice';

/** Compra num cartão de crédito (ou cópia de uma): quem paga é a fatura. */
export function isOnCard(t: Transaction): boolean {
    return (
        t.account?.type === 'credit' ||
        t.mirrored_from?.account?.type === 'credit'
    );
}

/**
 * Status de pagamento. No cartão: "na fatura" até a fatura ser paga (nunca "atrasado").
 */
export function paymentStatus(t: Transaction): PaymentStatus | null {
    if (t.paid_at) return 'paid';
    if (isOnCard(t)) return 'invoice';

    return t.date.slice(0, 10) < today() ? 'overdue' : 'pending';
}

/**
 * Quem marca como pago é quem pagou:
 * - na sua transação: você, a não ser que o pagador seja um contato que usa o Phamani;
 * - numa cópia compartilhada com você: só se foi você quem pagou.
 */
export function canMarkPaid(t: Transaction): boolean {
    if (isOnCard(t)) return false;
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

/**
 * Quando o dinheiro sai: compra no cartão = dia em que a fatura foi paga ou, se ainda não foi,
 * o vencimento (também na cópia de quem dividiu); o resto = a própria data.
 */
export function paymentDate(t: Transaction): string {
    const invoice = t.invoice ?? t.mirrored_from?.invoice;

    return (invoice?.paid_at ?? invoice?.due_date ?? t.date).slice(0, 10);
}

/** Fatura da compra (a sua ou a da original, na cópia). null = não é de cartão. */
export function invoiceOf(
    t: Transaction,
): { key: string; label: string } | null {
    if (t.invoice) {
        return {
            key: t.invoice.id,
            label: `Fatura ${t.account?.name ?? ''}`.trim(),
        };
    }

    const source = t.mirrored_from;
    if (source?.invoice) {
        const card = source.account?.name ?? 'cartão';
        const owner = source.user?.name;
        return {
            key: source.invoice.id,
            label: owner ? `Fatura ${card} (${owner})` : `Fatura ${card}`,
        };
    }

    return null;
}
