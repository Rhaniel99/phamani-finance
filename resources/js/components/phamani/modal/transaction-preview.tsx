import { Calendar, Receipt } from 'lucide-react';
import { motion } from 'motion/react';
import { CategoryIcon } from '@/components/phamani/category-icon';
import { useEnums } from '@/hooks/use-enums';
import { resolveEnumLabel } from '@/lib/enum-helpers';
import { formatCurrency, formatDate } from '@/lib/format';
import { getNextTransactionDate } from '@/lib/transaction-dates';
import { getInstallmentValue } from '@/lib/transaction-math';
import type { Account, Category, TransactionFormData } from '@/types/phamani';

interface TransactionPreviewProps {
    data: TransactionFormData;
    categories: Category[];
    accounts: Account[];
}

export function TransactionPreview({
    data,
    categories,
    accounts,
}: TransactionPreviewProps) {
    const { recurringFrequencies } = useEnums();

    const category = categories.find((c) => c.id === data.category_id) ?? null;
    const account = accounts.find((a) => a.id === data.account_id) ?? null;
    const amount = Number(data.amount || 0);
    const installmentValue = getInstallmentValue(
        amount,
        data.installments_count,
    );
    const nextDate = getNextTransactionDate(data);
    const frequencyLabel = resolveEnumLabel(
        recurringFrequencies,
        data.frequency,
    )?.toLowerCase();
    const isIncome = data.type === 'income';

    return (
        <div className="relative hidden w-1/2 flex-col items-center justify-center overflow-hidden border-l-2 border-[#D4C5A9] bg-[#E8DCC4]/50 p-12 md:flex">
            <div className="absolute top-0 right-0 h-64 w-64 rounded-full bg-[#D4C5A9]/20 blur-3xl" />
            <div className="absolute bottom-0 left-0 h-64 w-64 rounded-full bg-[#6B4E3D]/10 blur-3xl" />

            <p className="z-10 mt-12 mb-8 text-sm font-bold tracking-widest text-[#6B4E3D] uppercase">
                Pré-visualização
            </p>

            <motion.div
                key={data.type}
                initial={{ scale: 0.95, opacity: 0.8 }}
                animate={{ scale: 1, opacity: 1 }}
                className="z-10 w-full max-w-sm rounded-[2rem] border border-white/50 bg-[#F5EFE6] p-8 shadow-2xl"
            >
                <div className="mb-8 flex items-start justify-between">
                    <div
                        className={`rounded-2xl p-4 ${isIncome ? 'bg-[#E3F9E5] text-[#1F5428]' : 'bg-[#FCE7E7] text-[#D4183D]'}`}
                    >
                        <Receipt className="h-8 w-8" />
                    </div>

                    <div className="text-right">
                        <p className="mb-1 text-sm font-medium text-[#8B7355]">
                            {account?.name ?? '—'}
                        </p>
                        <p className="text-xs font-bold text-[#3D2817] uppercase opacity-60">
                            Conta
                        </p>
                    </div>
                </div>

                <div className="mb-8">
                    <p className="mb-2 text-sm font-medium text-[#8B7355]">
                        Valor
                    </p>
                    <h3
                        className={`text-4xl font-bold ${isIncome ? 'text-[#1F5428]' : 'text-[#D4183D]'}`}
                    >
                        {isIncome ? '+' : '-'} {formatCurrency(amount)}
                    </h3>
                </div>

                <div className="space-y-4">
                    <div className="flex items-center gap-4 rounded-xl bg-white/50 p-3">
                        {category ? (
                            <CategoryIcon
                                category={category}
                                className="h-9 w-9"
                                iconClassName="h-5 w-5"
                            />
                        ) : (
                            <div className="rounded-lg bg-[#E8DCC4] p-2">
                                <Receipt className="h-5 w-5 text-[#6B4E3D]" />
                            </div>
                        )}
                        <div>
                            <p className="text-sm font-bold text-[#3D2817]">
                                {data.description || 'Sem descrição'}
                            </p>
                            <p className="text-xs text-[#8B7355]">
                                {category?.name ?? 'Sem categoria'}
                            </p>
                        </div>
                    </div>

                    <div className="flex items-center gap-4 rounded-xl bg-white/50 p-3">
                        <div className="rounded-lg bg-[#E8DCC4] p-2 text-[#6B4E3D]">
                            <Calendar className="h-5 w-5" />
                        </div>
                        <div>
                            <p className="text-sm font-bold text-[#3D2817]">
                                {formatDate(data.date)}
                            </p>

                            {data.is_recurring && (
                                <>
                                    <p className="text-xs text-[#8B7355]">
                                        Repete: {frequencyLabel}
                                    </p>
                                    <p className="text-xs font-medium text-[#6B4E3D]">
                                        Próxima: {nextDate}
                                    </p>
                                </>
                            )}

                            {data.is_installment && (
                                <>
                                    <p className="text-xs text-[#8B7355]">
                                        Parcela 1 de {data.installments_count}
                                    </p>
                                    <p className="text-xs text-[#8B7355]">
                                        {formatCurrency(installmentValue)} por
                                        parcela
                                    </p>
                                    <p className="text-xs font-medium text-[#6B4E3D]">
                                        Próxima: {nextDate}
                                    </p>
                                </>
                            )}
                        </div>
                    </div>
                </div>
            </motion.div>
        </div>
    );
}
