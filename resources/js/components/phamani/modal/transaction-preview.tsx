import { Calendar, Receipt, Users } from 'lucide-react';
import { motion } from 'motion/react';
import { CategoryIcon } from '@/components/phamani/category-icon';
import { useEnums } from '@/hooks/use-enums';
import { resolveEnumLabel } from '@/lib/enum-helpers';
import { formatCurrency, formatDate } from '@/lib/format';
import { getNextTransactionDate } from '@/lib/transaction-dates';
import { ContactAvatar } from '@/components/phamani/contact-avatar';
import { TagChips } from '@/components/phamani/tag-input';
import { useAuth } from '@/hooks/use-auth';
import { useContacts } from '@/hooks/use-contacts';
import { splitBreakdown } from '@/lib/split';
import { getInstallmentValue } from '@/lib/transaction-math';
import { ACCOUNT_TYPE_LABELS } from '@/types/phamani';
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
    const contacts = useContacts();
    const { avatarUrl } = useAuth();

    const category = categories.find((c) => c.id === data.category_id) ?? null;
    const account = accounts.find((a) => a.id === data.account_id) ?? null;
    const amount = Number(data.amount || 0);
    const installmentValue = getInstallmentValue(
        amount,
        data.installments_count,
        data.installment_start,
        data.amount_mode,
    );
    const nextDate = getNextTransactionDate(data);
    const frequencyLabel = resolveEnumLabel(
        recurringFrequencies,
        data.frequency,
    )?.toLowerCase();
    const isIncome = data.type === 'income';

    // Divisão: no parcelado é por parcela.
    const splitBase =
        data.is_installment && installmentValue ? installmentValue : amount;
    const breakdown = splitBreakdown(splitBase, data.split);
    const nameOf = (id: string | null) =>
        id === null ? 'Você' : (contacts.find((c) => c.id === id)?.name ?? '—');
    const payerName = nameOf(data.split?.paid_by_contact_id ?? null);
    // Compra para outra pessoa: só os contatos aparecem, com o valor a receber.
    const forOthers = data.split?.include_me === false;
    const rows = forOthers
        ? breakdown.filter((b) => b.contact_id !== null)
        : breakdown;

    return (
        <div className="relative hidden w-[42%] flex-col items-center justify-center overflow-hidden border-l-2 border-[#D4C5A9] bg-[#E8DCC4]/50 p-12 md:flex">
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
                            {account
                                ? ACCOUNT_TYPE_LABELS[account.type]
                                : 'Conta'}
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
                    {rows.length > 0 && (
                        <div className="rounded-xl bg-white/50 p-3">
                            <div className="mb-2 flex items-center justify-between">
                                <span className="flex items-center gap-2 text-sm font-bold text-[#3D2817]">
                                    <Users className="h-4 w-4 text-[#6B4E3D]" />
                                    {forOthers ? 'Compra para' : 'Divisão'}
                                    {data.is_installment && (
                                        <span className="text-xs font-normal text-[#8B7355]">
                                            por parcela
                                        </span>
                                    )}
                                </span>
                                <span className="text-xs text-[#8B7355]">
                                    {forOthers ? (
                                        <strong className="text-[#3D2817]">
                                            A receber
                                        </strong>
                                    ) : (
                                        <>
                                            Pago por{' '}
                                            <strong className="text-[#3D2817]">
                                                {payerName === 'Você'
                                                    ? 'você'
                                                    : payerName}
                                            </strong>
                                        </>
                                    )}
                                </span>
                            </div>
                            <ul className="space-y-1">
                                {rows.map((b) => (
                                    <li
                                        key={b.contact_id ?? 'me'}
                                        className="flex items-center justify-between text-sm"
                                    >
                                        <span
                                            className={
                                                b.contact_id === null
                                                    ? 'flex items-center gap-2 font-semibold text-[#3D2817]'
                                                    : 'flex items-center gap-2 text-[#6B4E3D]'
                                            }
                                        >
                                            <ContactAvatar
                                                name={nameOf(b.contact_id)}
                                                avatar={
                                                    b.contact_id === null
                                                        ? avatarUrl
                                                        : contacts.find(
                                                              (c) =>
                                                                  c.id ===
                                                                  b.contact_id,
                                                          )?.linked_user?.avatar
                                                }
                                                className="h-6 w-6 text-[10px]"
                                            />
                                            {nameOf(b.contact_id)}
                                        </span>
                                        <span className="font-bold text-[#3D2817]">
                                            {formatCurrency(b.amount)}
                                        </span>
                                    </li>
                                ))}
                            </ul>
                        </div>
                    )}

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
                            <TagChips
                                tags={data.tags.map((name) => ({ name }))}
                                className="mt-1"
                            />
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
                                        Parcela {data.installment_start || 1} de{' '}
                                        {data.installments_count}
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
