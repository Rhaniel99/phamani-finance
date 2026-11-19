import type { InertiaFormProps } from '@inertiajs/react';
import { Layers, Repeat } from 'lucide-react';
import { useEffect, useState } from 'react';
import type { ReactNode } from 'react';
import { Form } from '@/components/form';
import { AccountDropdown } from '@/components/phamani/dropdown/account-dropdown';
import { CategoryDropdown } from '@/components/phamani/dropdown/category-dropdown';
import { SplitSection } from '@/components/phamani/modal/split-section';
import { ToggleField } from '@/components/toggle-field';
import { useEnums } from '@/hooks/use-enums';
import { formatCurrency } from '@/lib/format';
import { myShare } from '@/lib/split';
import { getInstallmentValue } from '@/lib/transaction-math';
import { cn } from '@/lib/utils';
import type { Account, Category, TransactionFormData } from '@/types/phamani';

interface TransactionFormProps {
    form: InertiaFormProps<TransactionFormData>;
    categories: Category[];
    accounts: Account[];
    onSubmit: () => void;
    onCreateCategory: () => void;
    onCreateAccount: () => void;
    /** Em edição não dá para transformar em parcelado/recorrente. */
    isEditing?: boolean;
    /** Editando uma parcela: oferece repetir o valor nas próximas. */
    isInstallmentParcel?: boolean;
}

const inputClass =
    'w-full rounded-xl border-2 border-[#E8DCC4] bg-white px-4 py-3 text-[#3D2817] focus:border-[#6B4E3D] focus:outline-none';
const labelClass = 'mb-2 ml-1 block font-serif text-sm text-[#6B4E3D]';

function FieldError({ message }: { message?: string }) {
    return message ? (
        <p className="mt-1 ml-1 text-xs text-[#D4183D]">{message}</p>
    ) : null;
}

export function TransactionForm({
    form,
    categories,
    accounts,
    onSubmit,
    onCreateCategory,
    onCreateAccount,
    isEditing = false,
    isInstallmentParcel = false,
}: TransactionFormProps) {
    const { data, setData, processing, errors } = form;
    const { recurringFrequencies } = useEnums();

    const filteredCategories = categories.filter(
        (c) => c.type === data.type || c.type === 'both',
    );
    const selectedCategory =
        categories.find((c) => c.id === data.category_id) ?? null;
    const selectedAccount =
        accounts.find((a) => a.id === data.account_id) ?? null;

    // Outra pessoa pagou: a conta não se aplica.
    const paidByOther = !!data.split?.paid_by_contact_id;

    // "Estou digitando: valor cheio | minha parte" (só em partes iguais com contatos).
    // O formulário sempre envia o valor cheio; em "minha parte" ele é calculado = parte × pessoas.
    const contactsInSplit =
        data.split?.participants.filter((p) => p.contact_id !== null).length ??
        0;
    const people = contactsInSplit + 1;
    const canEnterMine =
        !!data.split && data.split.mode === 'equal' && contactsInSplit > 0;
    const [enteredAs, setEnteredAs] = useState<'full' | 'mine'>('full');
    const [mineInput, setMineInput] = useState<number | ''>('');
    const mineMode = canEnterMine && enteredAs === 'mine';

    function toCents(value: number) {
        return Math.round(value * 100) / 100;
    }

    function switchEnteredAs(mode: 'full' | 'mine') {
        if (mode === 'mine') {
            setMineInput(
                data.amount ? toCents(Number(data.amount) / people) : '',
            );
        }
        setEnteredAs(mode);
    }

    // Mudou quem participa: recalcula o valor cheio a partir da sua parte.
    useEffect(() => {
        if (mineMode && mineInput !== '') {
            setData('amount', toCents(mineInput * people));
        }
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [people, mineMode]);

    // Ao trocar receita/despesa, invalida a categoria se ela não servir mais
    // (e desfaz a divisão: só despesas são divididas).
    useEffect(() => {
        if (data.type === 'income' && data.split) {
            setData('split', null);
        }
        if (
            selectedCategory &&
            selectedCategory.type !== data.type &&
            selectedCategory.type !== 'both'
        ) {
            setData('category_id', '');
        }
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [data.type]);

    // Pré-seleciona a primeira conta disponível.
    useEffect(() => {
        if (!data.account_id && accounts.length > 0) {
            setData('account_id', accounts[0].id);
        }
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [accounts]);

    return (
        <Form
            onSubmit={onSubmit}
            className="w-full overflow-y-auto bg-[#F5EFE6] p-8 md:w-1/2 md:p-12"
        >
            <h2 className="mb-8 text-2xl font-bold text-[#3D2817]">
                {isEditing ? 'Editar Transação' : 'Nova Transação'}
            </h2>

            <div className="space-y-6">
                <div className="flex rounded-xl bg-[#E8DCC4] p-1">
                    {(['expense', 'income'] as const).map((type) => (
                        <button
                            key={type}
                            type="button"
                            onClick={() => setData('type', type)}
                            className={cn(
                                'flex-1 rounded-lg py-3 text-sm font-bold transition-all',
                                data.type === type
                                    ? type === 'expense'
                                        ? 'bg-[#FCE7E7] text-[#D4183D] shadow-sm'
                                        : 'bg-[#E3F9E5] text-[#1F5428] shadow-sm'
                                    : 'text-[#6B4E3D] hover:bg-[#D4C5A9]/50',
                            )}
                        >
                            {type === 'expense' ? 'Despesa' : 'Receita'}
                        </button>
                    ))}
                </div>

                <div>
                    <label htmlFor="amount" className={labelClass}>
                        {mineMode
                            ? data.is_installment &&
                              data.amount_mode === 'installment'
                                ? 'Sua parte da parcela'
                                : 'Sua parte'
                            : data.is_installment
                              ? data.amount_mode === 'installment'
                                  ? 'Valor da parcela'
                                  : 'Valor total da compra'
                              : 'Valor'}
                    </label>
                    <div className="relative">
                        <span className="absolute top-1/2 left-4 -translate-y-1/2 font-bold text-[#8B7355]">
                            R$
                        </span>
                        <input
                            id="amount"
                            type="number"
                            inputMode="decimal"
                            step="0.01"
                            min="0.01"
                            value={mineMode ? mineInput : data.amount}
                            onChange={(e) => {
                                const v =
                                    e.target.value === ''
                                        ? ''
                                        : Number(e.target.value);
                                if (mineMode) {
                                    setMineInput(v);
                                    setData(
                                        'amount',
                                        v === '' ? '' : toCents(v * people),
                                    );
                                } else {
                                    setData('amount', v);
                                }
                            }}
                            placeholder="0,00"
                            className="w-full rounded-xl border-2 border-[#E8DCC4] bg-white py-4 pr-4 pl-12 text-2xl font-bold text-[#3D2817] placeholder:text-[#D4C5A9] focus:border-[#6B4E3D] focus:outline-none"
                        />
                    </div>
                    {canEnterMine && (
                        <div className="mt-2 flex items-center gap-2">
                            <span className="ml-1 text-xs text-[#8B7355]">
                                Estou digitando:
                            </span>
                            <div className="flex rounded-lg bg-[#E8DCC4] p-0.5">
                                {(
                                    [
                                        ['full', 'Valor cheio'],
                                        ['mine', 'Minha parte'],
                                    ] as const
                                ).map(([mode, label]) => (
                                    <button
                                        key={mode}
                                        type="button"
                                        onClick={() => switchEnteredAs(mode)}
                                        aria-pressed={enteredAs === mode}
                                        className={cn(
                                            'rounded-md px-3 py-1 text-xs font-bold transition-all',
                                            enteredAs === mode
                                                ? 'bg-white text-[#3D2817] shadow-sm'
                                                : 'text-[#6B4E3D] hover:bg-[#D4C5A9]/50',
                                        )}
                                    >
                                        {label}
                                    </button>
                                ))}
                            </div>
                        </div>
                    )}
                    <FieldError message={errors.amount} />
                </div>

                <div>
                    <label htmlFor="description" className={labelClass}>
                        Descrição
                    </label>
                    <input
                        id="description"
                        value={data.description}
                        onChange={(e) => setData('description', e.target.value)}
                        placeholder="Ex: Compras do mês"
                        className={inputClass}
                    />
                    <FieldError message={errors.description} />
                </div>

                <div
                    className={cn(
                        'grid gap-4',
                        paidByOther ? 'grid-cols-1' : 'grid-cols-2',
                    )}
                >
                    <div>
                        <span className={labelClass}>Categoria</span>
                        <CategoryDropdown
                            value={selectedCategory}
                            categories={filteredCategories}
                            onChange={(c) => setData('category_id', c.id)}
                            onCreate={onCreateCategory}
                        />
                        <FieldError message={errors.category_id} />
                    </div>
                    {!paidByOther && (
                        <div>
                            <span className={labelClass}>Conta</span>
                            <AccountDropdown
                                value={selectedAccount}
                                accounts={accounts}
                                onChange={(a) => setData('account_id', a.id)}
                                onCreate={onCreateAccount}
                            />
                            <FieldError message={errors.account_id} />
                        </div>
                    )}
                </div>

                <div>
                    <label htmlFor="date" className={labelClass}>
                        Data
                    </label>
                    <input
                        id="date"
                        type="date"
                        value={data.date}
                        onChange={(e) => setData('date', e.target.value)}
                        className={inputClass}
                    />
                    <FieldError message={errors.date} />
                </div>

                {data.type === 'expense' && (
                    <div className="border-t border-[#E8DCC4] pt-4">
                        <SplitSection
                            split={data.split}
                            onChange={(split) => setData('split', split)}
                            // Parcelado: a divisão é de cada parcela.
                            amount={
                                data.is_installment
                                    ? (getInstallmentValue(
                                          Number(data.amount || 0),
                                          data.installments_count,
                                          data.installment_start,
                                          data.amount_mode,
                                      ) ?? 0)
                                    : Number(data.amount || 0)
                            }
                            errors={errors as Record<string, string>}
                        />
                    </div>
                )}

                {isEditing && isInstallmentParcel && (
                    <div className="border-t border-[#E8DCC4] pt-4">
                        <ToggleField
                            label="Aplicar este valor às próximas parcelas"
                            icon={<Layers className="h-5 w-5" />}
                            active={data.apply_to_following}
                            onToggle={() =>
                                setData(
                                    'apply_to_following',
                                    !data.apply_to_following,
                                )
                            }
                        />
                    </div>
                )}

                {!isEditing && (
                    <div className="space-y-4 border-t border-[#E8DCC4] pt-4">
                        <ToggleField
                            label="Parcelado?"
                            icon={<Layers className="h-5 w-5" />}
                            active={data.is_installment}
                            onToggle={() =>
                                setData((prev) => ({
                                    ...prev,
                                    is_installment: !prev.is_installment,
                                    is_recurring: false,
                                }))
                            }
                        />

                        {data.is_installment && (
                            <div className="space-y-4 border-l-2 border-[#6B4E3D] pl-4">
                                <div>
                                    <span className={labelClass}>
                                        O valor informado é
                                    </span>
                                    <div className="flex rounded-xl bg-[#E8DCC4] p-1">
                                        {(
                                            [
                                                ['installment', 'Da parcela'],
                                                ['total', 'Total da compra'],
                                            ] as const
                                        ).map(([mode, label]) => (
                                            <button
                                                key={mode}
                                                type="button"
                                                onClick={() =>
                                                    setData('amount_mode', mode)
                                                }
                                                className={cn(
                                                    'flex-1 rounded-lg py-2 text-sm font-bold transition-all',
                                                    data.amount_mode === mode
                                                        ? 'bg-white text-[#3D2817] shadow-sm'
                                                        : 'text-[#6B4E3D] hover:bg-[#D4C5A9]/50',
                                                )}
                                            >
                                                {label}
                                            </button>
                                        ))}
                                    </div>
                                    <FieldError message={errors.amount_mode} />
                                </div>

                                <div className="grid grid-cols-2 gap-4">
                                    <div>
                                        <label
                                            htmlFor="installments_count"
                                            className={labelClass}
                                        >
                                            Nº de parcelas
                                        </label>
                                        <input
                                            id="installments_count"
                                            type="number"
                                            min={2}
                                            max={360}
                                            value={data.installments_count}
                                            onChange={(e) =>
                                                setData(
                                                    'installments_count',
                                                    Number(e.target.value),
                                                )
                                            }
                                            className="w-full rounded-xl border-2 border-[#E8DCC4] bg-white px-4 py-2 text-[#3D2817]"
                                        />
                                        <FieldError
                                            message={errors.installments_count}
                                        />
                                    </div>
                                    <div>
                                        <label
                                            htmlFor="installment_start"
                                            className={labelClass}
                                        >
                                            Começar da parcela
                                        </label>
                                        <input
                                            id="installment_start"
                                            type="number"
                                            min={1}
                                            max={data.installments_count}
                                            value={data.installment_start}
                                            onChange={(e) =>
                                                setData(
                                                    'installment_start',
                                                    Number(e.target.value),
                                                )
                                            }
                                            className="w-full rounded-xl border-2 border-[#E8DCC4] bg-white px-4 py-2 text-[#3D2817]"
                                        />
                                        <FieldError
                                            message={errors.installment_start}
                                        />
                                    </div>
                                </div>
                                <AutoPayToggle
                                    value={data.auto_pay}
                                    onChange={(v) => setData('auto_pay', v)}
                                />
                            </div>
                        )}

                        <ToggleField
                            label="Recorrente?"
                            icon={<Repeat className="h-5 w-5" />}
                            active={data.is_recurring}
                            onToggle={() =>
                                setData((prev) => ({
                                    ...prev,
                                    is_recurring: !prev.is_recurring,
                                    is_installment: false,
                                }))
                            }
                        />

                        {data.is_recurring && (
                            <div className="border-l-2 border-[#6B4E3D] pl-4">
                                <label
                                    htmlFor="frequency"
                                    className={labelClass}
                                >
                                    Frequência
                                </label>
                                <select
                                    id="frequency"
                                    value={data.frequency}
                                    onChange={(e) =>
                                        setData(
                                            'frequency',
                                            e.target
                                                .value as TransactionFormData['frequency'],
                                        )
                                    }
                                    className="w-full rounded-xl border-2 border-[#E8DCC4] bg-white px-4 py-2 text-[#3D2817]"
                                >
                                    {recurringFrequencies.map((freq) => (
                                        <option
                                            key={freq.value}
                                            value={freq.value}
                                        >
                                            {freq.label}
                                        </option>
                                    ))}
                                </select>
                                <FieldError message={errors.frequency} />
                                <AutoPayToggle
                                    value={data.auto_pay}
                                    onChange={(v) => setData('auto_pay', v)}
                                />
                            </div>
                        )}
                    </div>
                )}

                <TransactionSummary data={data} />

                <button
                    type="submit"
                    disabled={processing}
                    className="mt-8 w-full rounded-xl bg-[#3D2817] py-4 text-lg font-medium text-[#F5EFE6] shadow-lg transition-colors hover:bg-[#543924] disabled:opacity-50"
                >
                    {processing
                        ? 'Salvando...'
                        : isEditing
                          ? 'Salvar Alterações'
                          : 'Salvar Transação'}
                </button>
            </div>
        </Form>
    );
}

/**
 * Resumo fixo antes de salvar: quais parcelas serão lançadas, valor por parcela,
 * a sua parte (se dividida) e o total. Evita surpresa com "total × parcela × minha parte".
 */
function TransactionSummary({ data }: { data: TransactionFormData }) {
    const amount = Number(data.amount || 0);
    const hasSplit =
        !!data.split &&
        data.split.participants.some((p) => p.contact_id !== null);

    if (!amount || (!data.is_installment && !hasSplit)) return null;

    const parts: ReactNode[] = [];

    if (data.is_installment) {
        const count = data.installments_count || 0;
        const start = Math.min(Math.max(1, data.installment_start || 1), count);
        const launched = Math.max(0, count - start + 1);
        const perParcel =
            getInstallmentValue(amount, count, start, data.amount_mode) ?? 0;

        const which =
            launched <= 3
                ? Array.from(
                      { length: launched },
                      (_, i) => `${start + i}/${count}`,
                  ).join(', ')
                : `${start}/${count} a ${count}/${count} (${launched} parcelas)`;

        parts.push(
            <>
                Lança <strong>{which}</strong>
            </>,
            <>
                <strong>{formatCurrency(perParcel)}</strong> por parcela
            </>,
        );
        if (hasSplit) {
            parts.push(
                <>
                    sua parte{' '}
                    <strong>
                        {formatCurrency(myShare(perParcel, data.split))}
                    </strong>{' '}
                    por parcela
                </>,
            );
        }
        parts.push(
            <>
                {formatCurrency(perParcel * launched)} no total
                {start > 1 ? ' (das parcelas lançadas)' : ''}
            </>,
        );
    } else {
        parts.push(
            <>
                Valor cheio <strong>{formatCurrency(amount)}</strong>
            </>,
            <>
                sua parte{' '}
                <strong>{formatCurrency(myShare(amount, data.split))}</strong>
            </>,
        );
    }

    return (
        <div className="mt-6 rounded-2xl border border-[#D4C5A9] bg-[#FBF7F1] px-4 py-3 text-sm text-[#3D2817]">
            {parts.map((part, i) => (
                <span key={i}>
                    {i > 0 && <span className="text-[#8B7355]"> · </span>}
                    {part}
                </span>
            ))}
        </div>
    );
}

/** "Débito automático": no vencimento já marca como pago (senão fica pendente/atrasado). */
function AutoPayToggle({
    value,
    onChange,
}: {
    value: boolean;
    onChange: (value: boolean) => void;
}) {
    return (
        <label className="mt-3 flex cursor-pointer items-start gap-3 rounded-xl bg-white/60 p-3">
            <input
                type="checkbox"
                checked={value}
                onChange={(e) => onChange(e.target.checked)}
                className="mt-0.5 h-4 w-4 accent-[#3D2817]"
            />
            <span className="text-sm text-[#3D2817]">
                Débito automático
                <span className="block text-xs text-[#8B7355]">
                    No vencimento já entra como pago. Desligado, fica pendente
                    até você marcar (e aparece como atrasado se passar do dia).
                </span>
            </span>
        </label>
    );
}
