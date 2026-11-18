import { router } from '@inertiajs/react';
import {
    ArrowRight,
    Calendar,
    CreditCard,
    Pencil,
    Repeat,
    Tag,
    Trash2,
    X,
} from 'lucide-react';
import { AnimatePresence, motion } from 'motion/react';
import { useState } from 'react';
import { InstallmentModal } from '@/components/phamani/modal/installment-modal';
import { useEnums } from '@/hooks/use-enums';
import { resolveEnumLabel } from '@/lib/enum-helpers';
import { formatCurrency, formatDate } from '@/lib/format';
import { destroy } from '@/routes/transactions';
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
    const { recurringFrequencies } = useEnums();

    const isIncome = transaction?.type === 'income';
    const isInstallment = !!transaction?.installment_id;
    const confirming = !!transaction && confirmingId === transaction.id;

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
                                        value={transaction.account?.name ?? '—'}
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
                                        </div>
                                    )}
                                </div>

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
                                {confirming ? (
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
