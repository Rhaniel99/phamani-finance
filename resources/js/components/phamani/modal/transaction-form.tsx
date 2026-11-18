import type { InertiaFormProps } from '@inertiajs/react';
import { Layers, Repeat } from 'lucide-react';
import { useEffect } from 'react';
import { Form } from '@/components/form';
import { AccountDropdown } from '@/components/phamani/dropdown/account-dropdown';
import { CategoryDropdown } from '@/components/phamani/dropdown/category-dropdown';
import { ToggleField } from '@/components/toggle-field';
import { useEnums } from '@/hooks/use-enums';
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

    // Ao trocar receita/despesa, invalida a categoria se ela não servir mais.
    useEffect(() => {
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
                        Valor
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
                            value={data.amount}
                            onChange={(e) =>
                                setData(
                                    'amount',
                                    e.target.value === ''
                                        ? ''
                                        : Number(e.target.value),
                                )
                            }
                            placeholder="0,00"
                            className="w-full rounded-xl border-2 border-[#E8DCC4] bg-white py-4 pr-4 pl-12 text-2xl font-bold text-[#3D2817] placeholder:text-[#D4C5A9] focus:border-[#6B4E3D] focus:outline-none"
                        />
                    </div>
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

                <div className="grid grid-cols-2 gap-4">
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
                            <div className="border-l-2 border-[#6B4E3D] pl-4">
                                <label
                                    htmlFor="installments_count"
                                    className={labelClass}
                                >
                                    Número de Parcelas
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
                            </div>
                        )}
                    </div>
                )}

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
