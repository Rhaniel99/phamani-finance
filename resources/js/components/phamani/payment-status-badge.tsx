import { cn } from '@/lib/utils';
import type { PaymentStatus } from '@/lib/payment';

const STYLES: Record<PaymentStatus, string> = {
    paid: 'bg-[#E3F9E5] text-[#1F5428]',
    pending: 'bg-[#E8DCC4] text-[#6B4E3D]',
    overdue: 'bg-[#FCE7E7] text-[#A65D57]',
};

export function paymentStatusLabel(
    status: PaymentStatus,
    isIncome: boolean,
): string {
    if (status === 'paid') return isIncome ? 'Recebido' : 'Pago';
    if (status === 'overdue') return 'Atrasado';

    return 'Pendente';
}

export function PaymentStatusBadge({
    status,
    isIncome = false,
    className,
}: {
    status: PaymentStatus;
    isIncome?: boolean;
    className?: string;
}) {
    return (
        <span
            className={cn(
                'inline-flex items-center rounded-md px-1.5 py-0.5 text-[10px] font-bold tracking-wide uppercase',
                STYLES[status],
                className,
            )}
        >
            {paymentStatusLabel(status, isIncome)}
        </span>
    );
}
