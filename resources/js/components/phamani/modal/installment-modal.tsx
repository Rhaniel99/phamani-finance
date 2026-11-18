import { Calendar, Check, Clock, CreditCard, X } from 'lucide-react';
import { AnimatePresence, motion } from 'motion/react';
import { formatCurrency, formatDate, today } from '@/lib/format';
import type { InstallmentInfo } from '@/types/phamani';

interface InstallmentModalProps {
    isOpen: boolean;
    onClose: () => void;
    installment: InstallmentInfo;
}

type Status = 'paid' | 'pending' | 'future';

export function InstallmentModal({
    isOpen,
    onClose,
    installment,
}: InstallmentModalProps) {
    const now = today();
    const items = installment.transactions ?? [];
    // A próxima parcela ainda não vencida é a "pendente"; anteriores já passaram; o resto é futuro.
    const nextPending = items.find(
        (i) => i.date.slice(0, 10) >= now,
    )?.installment_number;

    const statusOf = (number: number, date: string): Status => {
        if (date.slice(0, 10) < now) return 'paid';
        return number === nextPending ? 'pending' : 'future';
    };

    return (
        <AnimatePresence>
            {isOpen && (
                <div className="fixed inset-0 z-[70] flex items-center justify-center bg-[#3D2817]/60 p-4 backdrop-blur-sm">
                    <motion.div
                        initial={{ opacity: 0, scale: 0.95, y: 20 }}
                        animate={{ opacity: 1, scale: 1, y: 0 }}
                        exit={{ opacity: 0, scale: 0.95, y: 20 }}
                        className="flex max-h-[80vh] w-full max-w-2xl flex-col overflow-hidden rounded-[2rem] bg-[#F5EFE6] shadow-2xl"
                    >
                        <div className="flex items-center justify-between border-b border-[#E8DCC4] bg-[#F5EFE6] p-6">
                            <div className="flex items-center gap-4">
                                <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-[#E8DCC4] text-[#6B4E3D]">
                                    <CreditCard className="h-6 w-6" />
                                </div>
                                <div>
                                    <h3 className="text-xl font-bold text-[#3D2817]">
                                        Parcelamento
                                    </h3>
                                    <p className="text-sm text-[#6B4E3D]">
                                        {installment.name} ·{' '}
                                        {installment.installments}x · total{' '}
                                        {formatCurrency(
                                            installment.total_amount,
                                        )}
                                    </p>
                                </div>
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

                        <div className="flex-1 overflow-y-auto bg-[#FAF7F1] p-8">
                            <div className="relative">
                                <div className="absolute top-4 bottom-4 left-8 w-0.5 bg-[#E8DCC4]" />

                                <div className="space-y-6">
                                    {items.map((inst) => {
                                        const status = statusOf(
                                            inst.installment_number,
                                            inst.date,
                                        );

                                        return (
                                            <motion.div
                                                key={inst.id}
                                                initial={{ opacity: 0, x: -20 }}
                                                animate={{ opacity: 1, x: 0 }}
                                                transition={{
                                                    delay:
                                                        inst.installment_number *
                                                        0.05,
                                                }}
                                                className="relative flex items-center gap-6"
                                            >
                                                <div
                                                    className={`relative z-10 flex h-8 w-16 items-center justify-center rounded-full border-2 text-xs font-bold ${
                                                        status === 'paid'
                                                            ? 'border-[#6B4E3D] bg-[#6B4E3D] text-[#F5EFE6]'
                                                            : status ===
                                                                'pending'
                                                              ? 'border-[#6B4E3D] bg-[#F5EFE6] text-[#6B4E3D]'
                                                              : 'border-[#E8DCC4] bg-[#E8DCC4] text-[#8B7355]'
                                                    }`}
                                                >
                                                    {inst.installment_number}x
                                                </div>

                                                <div
                                                    className={`flex flex-1 items-center justify-between rounded-2xl border p-4 shadow-sm ${
                                                        status === 'pending'
                                                            ? 'border-[#6B4E3D]/30 bg-white shadow-md'
                                                            : 'border-[#E8DCC4] bg-white'
                                                    }`}
                                                >
                                                    <div className="flex items-center gap-3">
                                                        <div className="rounded-xl bg-[#F5EFE6] p-2 text-[#6B4E3D]">
                                                            <Calendar className="h-4 w-4" />
                                                        </div>
                                                        <div>
                                                            <p className="text-sm font-bold text-[#3D2817]">
                                                                {formatCurrency(
                                                                    inst.amount,
                                                                )}
                                                            </p>
                                                            <p className="text-xs text-[#8B7355]">
                                                                {formatDate(
                                                                    inst.date,
                                                                )}
                                                            </p>
                                                        </div>
                                                    </div>

                                                    {status === 'paid' && (
                                                        <div className="flex items-center gap-1 rounded-lg bg-[#E8DCC4]/50 px-3 py-1 text-xs font-bold text-[#6B4E3D]">
                                                            <Check className="h-3 w-3" />{' '}
                                                            Pago
                                                        </div>
                                                    )}
                                                    {status === 'pending' && (
                                                        <div className="flex items-center gap-1 rounded-lg bg-[#FCE7E7] px-3 py-1 text-xs font-bold text-[#D4183D]">
                                                            <Clock className="h-3 w-3" />{' '}
                                                            Próxima
                                                        </div>
                                                    )}
                                                </div>
                                            </motion.div>
                                        );
                                    })}
                                </div>
                            </div>
                        </div>
                    </motion.div>
                </div>
            )}
        </AnimatePresence>
    );
}
