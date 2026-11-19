import { Link, router } from '@inertiajs/react';
import {
    ArrowRight,
    Calendar,
    Check,
    CreditCard,
    Pencil,
    Repeat,
    Tag,
    Trash2,
    X,
} from 'lucide-react';
import { AnimatePresence, motion } from 'motion/react';
import { useState } from 'react';
import { SplitDetails } from '@/components/phamani/drawer/split-details';
import { PaymentStatusBadge } from '@/components/phamani/payment-status-badge';
import { canMarkPaid, payerName, paymentStatus } from '@/lib/payment';
import { InstallmentModal } from '@/components/phamani/modal/installment-modal';
import { useEnums } from '@/hooks/use-enums';
import { resolveEnumLabel } from '@/lib/enum-helpers';
import { formatCurrency, formatDate } from '@/lib/format';
import { cn } from '@/lib/utils';
import { inbox } from '@/routes';
import { autoPay as installmentAutoPay } from '@/routes/installments';
import {
    autoPay as recurringAutoPay,
    end as endRecurring,
} from '@/routes/recurring';
import {
    destroy,
    pay as payTransaction,
    unpay as unpayTransaction,
} from '@/routes/transactions';
import type { Transaction } from '@/types/phamani';

interface ShowTransactionDrawerProps {
    transaction: Transaction | null;
    onClose: () => void;
    onEdit: (transaction: Transaction) => void;
}

export function ShowTransactionDrawer({
    transaction,
    onClose,
    onEdit,
}: ShowTransactionDrawerProps) {
    const [showInstallments, setShowInstallments] = useState(false);
    // Guarda o id da transação em confirmação: trocar de transação cancela a confirmação.
    const [confirmingId, setConfirmingId] = useState<string | null>(null);
    const [deleting, setDeleting] = useState(false);
    const [endingId, setEndingId] = useState<string | null>(null);
    const { recurringFrequencies } = useEnums();

    const isIncome = transaction?.type === 'income';
    const isInstallment = !!transaction?.installment_id;
    const isMirror = !!transaction?.mirrored_from_id;
    const confirming = !!transaction && confirmingId === transaction.id;

    const recurringEnded = !!transaction?.recurring?.end_date;
    const confirmingEnd =
        !!transaction?.recurring && endingId === transaction.recurring.id;

    function handleEndRecurring() {
        const recurring = transaction?.recurring;
        if (!recurring) return;

        router.post(
            endRecurring.url(recurring.id),
            {},
            {
                preserveScroll: true,
                onSuccess: () => {
                    setEndingId(null);
                    onClose();
                },
            },
        );
    }

    function handleDelete() {
        if (!transaction) return;

        router.delete(destroy.url(transaction.id), {
            preserveScroll: true,
            onStart: () => setDeleting(true),
            onFinish: () => setDeleting(false),
            onSuccess: () => {
                setConfirmingId(null);
                onClose();
            },
        });
    }

    return (
        <>
            <AnimatePresence>
                {transaction && (
                    <>
                        <motion.div
                            initial={{ opacity: 0 }}
                            animate={{ opacity: 1 }}
                            exit={{ opacity: 0 }}
                            onClick={onClose}
                            className="fixed inset-0 z-50 bg-[#3D2817]/20 backdrop-blur-[1px]"
                        />
                        <motion.div
                            role="dialog"
                            aria-modal="true"
                            aria-label="Detalhes da transação"
                            initial={{ x: '100%' }}
                            animate={{ x: 0 }}
                            exit={{ x: '100%' }}
                            transition={{
                                type: 'spring',
                                damping: 25,
                                stiffness: 200,
                            }}
                            className="fixed top-0 right-0 z-[60] flex h-full w-full flex-col border-l-2 border-[#E8DCC4] bg-[#F5EFE6] shadow-2xl md:w-[480px]"
                        >
                            <div className="border-b border-[#D4C5A9] bg-[#F5EFE6] p-8">
                                <div className="mb-6 flex items-start justify-between">
                                    <div
                                        className={`rounded-2xl p-3 ${isIncome ? 'bg-[#E3F9E5] text-[#1F5428]' : 'bg-[#FCE7E7] text-[#D4183D]'}`}
                                    >
                                        <ArrowRight
                                            className={`h-6 w-6 ${isIncome ? '-rotate-45' : 'rotate-45'}`}
                                        />
                                    </div>
                                    <button
                                        type="button"
                                        onClick={onClose}
                                        aria-label="Fechar"
                                        className="rounded-xl p-2 text-[#6B4E3D] transition-colors hover:bg-[#E8DCC4]"
                                    >
                                        <X className="h-6 w-6" />
                                    </button>
                                </div>

                                <h2 className="mb-1 text-3xl font-bold text-[#3D2817]">
                                    {isIncome ? '+' : '-'}{' '}
                                    {formatCurrency(transaction.amount)}
                                </h2>
                                {transaction.total_amount != null && (
                                    <p className="mb-1 text-sm text-[#8B7355]">
                                        Sua parte de{' '}
                                        {formatCurrency(
                                            transaction.total_amount,
                                        )}
                                    </p>
                                )}
                                <p className="text-lg text-[#6B4E3D]">
                                    {transaction.name}
                                </p>
                            </div>

                            <div className="flex-1 space-y-8 overflow-y-auto p-8">
                                <div className="grid grid-cols-2 gap-4">
                                    <MetaCard
                                        icon={<Tag className="h-4 w-4" />}
                                        label="Categoria"
                                        value={
                                            transaction.category?.name ?? '—'
                                        }
                                    />
                                    <MetaCard
                                        icon={
                                            <CreditCard className="h-4 w-4" />
                                        }
                                        label="Conta"
                                        value={
                                            transaction.account?.name ??
                                            (transaction.paid_by
                                                ? `Pago por ${transaction.paid_by.name}`
                                                : '—')
                                        }
                                    />
                                    <MetaCard
                                        icon={<Calendar className="h-4 w-4" />}
                                        label="Data"
                                        value={formatDate(transaction.date)}
                                    />

                                    {transaction.recurring && (
                                        <div className="rounded-2xl border border-[#6B4E3D] bg-[#6B4E3D] p-4 shadow-sm">
                                            <div className="mb-2 flex items-center gap-2 text-[#F5EFE6]/70">
                                                <Repeat className="h-4 w-4" />
                                                <span className="text-xs font-bold tracking-wider uppercase">
                                                    Recorrência
                                                </span>
                                            </div>
                                            <p className="font-medium text-[#F5EFE6]">
                                                {resolveEnumLabel(
                                                    recurringFrequencies,
                                                    transaction.recurring
                                                        .frequency,
                                                )}
                                            </p>
                                            {recurringEnded && (
                                                <p className="mt-1 text-xs text-[#F5EFE6]/70">
                                                    Encerrada em{' '}
                                                    {formatDate(
                                                        transaction.recurring
                                                            .end_date,
                                                    )}
                                                </p>
                                            )}
                                        </div>
                                    )}
                                </div>

                                <PaymentStatusBlock
                                    transaction={transaction}
                                    onDone={onClose}
                                />

                                <SplitDetails transaction={transaction} />

                                {!isMirror && (
                                    <AutoPaySwitch transaction={transaction} />
                                )}

                                {transaction.recurring && !recurringEnded && (
                                    <div className="rounded-3xl border border-[#D4C5A9] bg-[#E8DCC4]/50 p-6">
                                        <p className="mb-4 text-sm text-[#6B4E3D]">
                                            Todo vencimento o Phamani lança esta
                                            transação repetindo o último valor.
                                            Se mudar num mês, é só editar a
                                            ocorrência daquele mês.
                                        </p>
                                        {confirmingEnd ? (
                                            <div className="flex gap-3">
                                                <button
                                                    type="button"
                                                    onClick={() =>
                                                        setEndingId(null)
                                                    }
                                                    className="flex-1 rounded-xl border-2 border-[#D4C5A9] py-2 text-sm font-medium text-[#6B4E3D] hover:bg-[#E8DCC4]"
                                                >
                                                    Cancelar
                                                </button>
                                                <button
                                                    type="button"
                                                    onClick={handleEndRecurring}
                                                    className="flex-1 rounded-xl bg-[#6B4E3D] py-2 text-sm font-medium text-[#F5EFE6] hover:bg-[#3D2817]"
                                                >
                                                    Confirmar
                                                </button>
                                            </div>
                                        ) : (
                                            <button
                                                type="button"
                                                onClick={() =>
                                                    setEndingId(
                                                        transaction.recurring
                                                            ?.id ?? null,
                                                    )
                                                }
                                                className="w-full rounded-xl border-2 border-[#6B4E3D] py-2 text-sm font-medium text-[#6B4E3D] transition-colors hover:bg-[#6B4E3D] hover:text-[#F5EFE6]"
                                            >
                                                Encerrar recorrência
                                            </button>
                                        )}
                                    </div>
                                )}

                                {transaction.installment && (
                                    <div className="flex items-center justify-between rounded-3xl border border-[#D4C5A9] bg-[#E8DCC4]/50 p-6">
                                        <div>
                                            <h4 className="mb-1 font-bold text-[#3D2817]">
                                                Parcelamento
                                            </h4>
                                            <p className="text-sm text-[#6B4E3D]">
                                                Parcela{' '}
                                                {transaction.installment_number}
                                                /
                                                {
                                                    transaction.installment
                                                        .installments
                                                }
                                            </p>
                                        </div>
                                        <button
                                            type="button"
                                            onClick={() =>
                                                setShowInstallments(true)
                                            }
                                            className="rounded-xl bg-[#6B4E3D] px-4 py-2 text-sm font-medium text-[#F5EFE6] shadow-md transition-colors hover:bg-[#3D2817]"
                                        >
                                            Ver Linha do Tempo
                                        </button>
                                    </div>
                                )}
                            </div>

                            <div className="border-t border-[#D4C5A9] bg-[#FAF7F1] p-6 md:p-8">
                                {isMirror ? (
                                    <div className="space-y-2 text-sm text-[#6B4E3D]">
                                        <p>
                                            Divisão compartilhada por{' '}
                                            <strong>
                                                {transaction.mirrored_from?.user
                                                    ?.name ?? 'outra pessoa'}
                                            </strong>
                                            . Só quem criou pode alterar os
                                            valores.
                                        </p>
                                        <Link
                                            href={inbox.url()}
                                            className="font-medium text-[#3D2817] underline"
                                        >
                                            Sair da divisão em Pendências
                                        </Link>
                                    </div>
                                ) : confirming ? (
                                    <div className="space-y-4">
                                        <p className="text-sm text-[#6B4E3D]">
                                            {isInstallment
                                                ? 'Excluir o parcelamento inteiro (todas as parcelas)? Essa ação não pode ser desfeita.'
                                                : 'Excluir esta transação? Essa ação não pode ser desfeita.'}
                                        </p>
                                        <div className="flex gap-4">
                                            <button
                                                type="button"
                                                onClick={() =>
                                                    setConfirmingId(null)
                                                }
                                                disabled={deleting}
                                                className="flex-1 rounded-xl border-2 border-[#D4C5A9] py-3 font-medium text-[#6B4E3D] transition-colors hover:bg-[#E8DCC4] disabled:opacity-50"
                                            >
                                                Cancelar
                                            </button>
                                            <button
                                                type="button"
                                                onClick={handleDelete}
                                                disabled={deleting}
                                                className="flex flex-1 items-center justify-center gap-2 rounded-xl bg-[#A65D57] py-3 font-medium text-white transition-colors hover:bg-[#8B4543] disabled:opacity-50"
                                            >
                                                <Trash2 className="h-4 w-4" />
                                                {deleting
                                                    ? 'Excluindo...'
                                                    : 'Excluir'}
                                            </button>
                                        </div>
                                    </div>
                                ) : (
                                    <div className="flex gap-4">
                                        <button
                                            type="button"
                                            onClick={() => onEdit(transaction)}
                                            className="flex flex-1 items-center justify-center gap-2 rounded-xl border-2 border-[#D4C5A9] py-3 font-medium text-[#6B4E3D] transition-colors hover:bg-[#E8DCC4]"
                                        >
                                            <Pencil className="h-4 w-4" />
                                            Editar
                                        </button>
                                        <button
                                            type="button"
                                            onClick={() =>
                                                setConfirmingId(transaction.id)
                                            }
                                            className="flex flex-1 items-center justify-center gap-2 rounded-xl bg-[#D4C5A9] py-3 font-medium text-[#3D2817] transition-colors hover:bg-[#C9B59A]"
                                        >
                                            <Trash2 className="h-4 w-4" />
                                            Excluir
                                        </button>
                                    </div>
                                )}
                            </div>
                        </motion.div>
                    </>
                )}
            </AnimatePresence>

            {transaction?.installment && (
                <InstallmentModal
                    isOpen={showInstallments}
                    onClose={() => setShowInstallments(false)}
                    installment={transaction.installment}
                />
            )}
        </>
    );
}

function MetaCard({
    icon,
    label,
    value,
}: {
    icon: React.ReactNode;
    label: string;
    value: string;
}) {
    return (
        <div className="rounded-2xl border border-[#E8DCC4] bg-white p-4 shadow-sm">
            <div className="mb-2 flex items-center gap-2 text-[#8B7355]">
                {icon}
                <span className="text-xs font-bold tracking-wider uppercase">
                    {label}
                </span>
            </div>
            <p className="font-medium text-[#3D2817]">{value}</p>
        </div>
    );
}

/** Status de pagamento + ação de marcar como pago/pendente (só quem pagou). */
function PaymentStatusBlock({
    transaction,
    onDone,
}: {
    transaction: Transaction;
    onDone: () => void;
}) {
    const [busy, setBusy] = useState(false);
    const status = paymentStatus(transaction);
    if (!status) return null;

    const isIncome = transaction.type === 'income';
    const canMark = canMarkPaid(transaction);
    const opts = {
        preserveScroll: true,
        onStart: () => setBusy(true),
        onFinish: () => setBusy(false),
        onSuccess: onDone,
    };

    return (
        <div
            className={cn(
                'flex flex-wrap items-center justify-between gap-3 rounded-3xl border p-5',
                status === 'overdue'
                    ? 'border-[#A65D57] bg-[#FDF3F2]'
                    : 'border-[#D4C5A9] bg-white',
            )}
        >
            <div>
                <div className="flex items-center gap-2">
                    <PaymentStatusBadge status={status} isIncome={isIncome} />
                    {transaction.paid_at && (
                        <span className="text-xs text-[#8B7355]">
                            em {formatDate(transaction.paid_at)}
                        </span>
                    )}
                </div>
                {!canMark && (
                    <p className="mt-1 text-xs text-[#8B7355]">
                        Quem marca é quem pagou
                        {payerName(transaction)
                            ? ` (${payerName(transaction)})`
                            : ''}
                        .
                    </p>
                )}
            </div>

            {canMark &&
                (status === 'paid' ? (
                    <button
                        type="button"
                        disabled={busy}
                        onClick={() =>
                            router.delete(
                                unpayTransaction.url(transaction.id),
                                opts,
                            )
                        }
                        className="rounded-xl border-2 border-[#D4C5A9] px-4 py-2 text-sm font-medium text-[#6B4E3D] hover:bg-[#E8DCC4] disabled:opacity-50"
                    >
                        Voltar para pendente
                    </button>
                ) : (
                    <button
                        type="button"
                        disabled={busy}
                        onClick={() =>
                            router.post(
                                payTransaction.url(transaction.id),
                                {},
                                opts,
                            )
                        }
                        className="flex items-center gap-2 rounded-xl bg-[#1F5428] px-4 py-2 text-sm font-medium text-white hover:bg-[#173F1E] disabled:opacity-50"
                    >
                        <Check className="h-4 w-4" />
                        {isIncome ? 'Marcar como recebida' : 'Marcar como paga'}
                    </button>
                ))}
        </div>
    );
}

/** Débito automático da série (recorrência ou parcelamento) desta transação. */
function AutoPaySwitch({ transaction }: { transaction: Transaction }) {
    const [busy, setBusy] = useState(false);
    const series = transaction.recurring
        ? {
              enabled: !!transaction.recurring.auto_pay,
              url: recurringAutoPay.url(transaction.recurring.id),
              label: 'recorrência',
          }
        : transaction.installment && transaction.installment_id
          ? {
                enabled: !!transaction.installment.auto_pay,
                url: installmentAutoPay.url(transaction.installment_id),
                label: 'parcelamento',
            }
          : null;

    if (!series || transaction.account?.type === 'credit') return null;

    return (
        <label className="flex cursor-pointer items-start gap-3 rounded-3xl border border-[#D4C5A9] bg-white p-5">
            <input
                type="checkbox"
                checked={series.enabled}
                disabled={busy}
                onChange={(e) =>
                    router.post(
                        series.url,
                        { enabled: e.target.checked },
                        {
                            preserveScroll: true,
                            onStart: () => setBusy(true),
                            onFinish: () => setBusy(false),
                        },
                    )
                }
                className="mt-0.5 h-4 w-4 accent-[#3D2817]"
            />
            <span className="text-sm text-[#3D2817]">
                Débito automático
                <span className="block text-xs text-[#8B7355]">
                    Vale para todo o {series.label}: no vencimento já entra como
                    pago. Ao ligar, o que já venceu e está em aberto é marcado
                    como pago.
                </span>
            </span>
        </label>
    );
}
