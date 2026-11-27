import { Banknote, CreditCard, PiggyBank, Trash2, Wallet } from 'lucide-react';
import { useState } from 'react';
import type { ElementType } from 'react';
import { Form } from '@/components/form';
import { DrawerShell } from '@/components/phamani/drawer/drawer-shell';
import { DeleteAccountModal } from '@/components/phamani/modal/delete-account-modal';
import { Label } from '@/components/ui/label';
import { useAccountsForm } from '@/hooks/use-accounts-form';
import { cn } from '@/lib/utils';
import type { Account, CreateAccount } from '@/types/phamani';

interface CreateAccountDrawerProps {
    isOpen: boolean;
    onClose: () => void;
    /** Contas do usuário, para escolher de onde sai o pagamento da fatura. */
    accounts?: Account[];
    /** Quando informado, edita esta conta/cartão. */
    account?: Account | null;
}

const TYPES: Array<{
    value: CreateAccount['type'];
    label: string;
    icon: ElementType;
}> = [
    { value: 'cash', label: 'Dinheiro', icon: Banknote },
    { value: 'checking', label: 'Conta', icon: Wallet },
    { value: 'savings', label: 'Poupança', icon: PiggyBank },
    { value: 'credit', label: 'Cartão de crédito', icon: CreditCard },
];

const inputClass =
    'w-full rounded-xl border-2 border-[#E8DCC4] bg-white px-4 py-3 text-[#3D2817] placeholder:text-[#D4C5A9] focus:border-[#6B4E3D] focus:outline-none';

function FieldError({ message }: { message?: string }) {
    return message ? <p className="text-xs text-[#D4183D]">{message}</p> : null;
}

export function CreateAccountDrawer({
    isOpen,
    onClose,
    accounts = [],
    account,
}: CreateAccountDrawerProps) {
    return (
        <DrawerShell
            isOpen={isOpen}
            onClose={onClose}
            title={
                account
                    ? account.type === 'credit'
                        ? 'Editar Cartão'
                        : 'Editar Conta'
                    : 'Nova Conta'
            }
        >
            {/* key: formulário novo a cada abertura/conta editada */}
            <AccountForm
                key={account?.id ?? 'new'}
                onClose={onClose}
                accounts={accounts}
                account={account}
            />
        </DrawerShell>
    );
}

function AccountForm({
    onClose,
    accounts,
    account,
}: {
    onClose: () => void;
    accounts: Account[];
    account?: Account | null;
}) {
    const { form, submit, isEditing } = useAccountsForm(onClose, account);
    const { data, setData, errors } = form;
    const isCard = data.type === 'credit';
    const paymentAccounts = accounts.filter((a) => a.type !== 'credit');
    const [deleting, setDeleting] = useState(false);

    return (
        <Form
            onSubmit={submit}
            className="flex flex-1 flex-col overflow-y-auto"
        >
            <div className="flex-1 space-y-8 p-6">
                <div className="space-y-3">
                    <Label
                        htmlFor="account-name"
                        className="font-serif text-[#6B4E3D]"
                    >
                        {isCard ? 'Nome do cartão' : 'Nome da conta'}
                    </Label>
                    <input
                        id="account-name"
                        value={data.name}
                        onChange={(e) => setData('name', e.target.value)}
                        placeholder={
                            isCard ? 'Ex: Nubank Platinum' : 'Ex: Nubank'
                        }
                        className={inputClass}
                    />
                    <FieldError message={errors.name} />
                </div>

                {!isEditing && (
                    <div className="space-y-3">
                        <Label className="font-serif text-[#6B4E3D]">
                            Tipo
                        </Label>
                        <div className="grid grid-cols-2 gap-3">
                            {TYPES.map(({ value, label, icon: Icon }) => (
                                <button
                                    key={value}
                                    type="button"
                                    onClick={() => setData('type', value)}
                                    className={cn(
                                        'flex flex-col items-center justify-center gap-2 rounded-xl border-2 p-4 transition-all',
                                        data.type === value
                                            ? 'border-[#3D2817] bg-white text-[#3D2817]'
                                            : 'border-transparent bg-white text-[#D4C5A9] hover:border-[#E8DCC4]',
                                    )}
                                >
                                    <Icon className="h-6 w-6" />
                                    <span className="text-xs font-medium">
                                        {label}
                                    </span>
                                </button>
                            ))}
                        </div>
                    </div>
                )}

                {isCard && (
                    <div className="space-y-5 rounded-2xl border border-[#E8DCC4] bg-[#FBF7F1] p-4">
                        <p className="text-xs text-[#8B7355]">
                            Compras no cartão não mexem no saldo das contas:
                            entram na fatura e o dinheiro só sai quando você
                            paga a fatura.
                        </p>

                        <div className="space-y-2">
                            <Label
                                htmlFor="credit_limit"
                                className="font-serif text-[#6B4E3D]"
                            >
                                Limite (R$)
                            </Label>
                            <input
                                id="credit_limit"
                                type="number"
                                inputMode="decimal"
                                step="0.01"
                                min="0"
                                value={data.credit_limit}
                                onChange={(e) =>
                                    setData(
                                        'credit_limit',
                                        e.target.value === ''
                                            ? ''
                                            : Number(e.target.value),
                                    )
                                }
                                placeholder="5000,00"
                                className={inputClass}
                            />
                            <FieldError message={errors.credit_limit} />
                        </div>

                        <div className="grid grid-cols-2 gap-3">
                            <div className="space-y-2">
                                <Label
                                    htmlFor="closing_day"
                                    className="font-serif text-[#6B4E3D]"
                                >
                                    Dia do fechamento
                                </Label>
                                <input
                                    id="closing_day"
                                    type="number"
                                    min={1}
                                    max={31}
                                    value={data.closing_day}
                                    onChange={(e) =>
                                        setData(
                                            'closing_day',
                                            e.target.value === ''
                                                ? ''
                                                : Number(e.target.value),
                                        )
                                    }
                                    placeholder="25"
                                    className={inputClass}
                                />
                                <FieldError message={errors.closing_day} />
                            </div>
                            <div className="space-y-2">
                                <Label
                                    htmlFor="due_day"
                                    className="font-serif text-[#6B4E3D]"
                                >
                                    Dia do vencimento
                                </Label>
                                <input
                                    id="due_day"
                                    type="number"
                                    min={1}
                                    max={31}
                                    value={data.due_day}
                                    onChange={(e) =>
                                        setData(
                                            'due_day',
                                            e.target.value === ''
                                                ? ''
                                                : Number(e.target.value),
                                        )
                                    }
                                    placeholder="5"
                                    className={inputClass}
                                />
                                <FieldError message={errors.due_day} />
                            </div>
                        </div>

                        {paymentAccounts.length > 0 && (
                            <div className="space-y-2">
                                <Label
                                    htmlFor="payment_account_id"
                                    className="font-serif text-[#6B4E3D]"
                                >
                                    Conta que paga a fatura
                                </Label>
                                <select
                                    id="payment_account_id"
                                    value={data.payment_account_id}
                                    onChange={(e) =>
                                        setData(
                                            'payment_account_id',
                                            e.target.value,
                                        )
                                    }
                                    className={inputClass}
                                >
                                    <option value="">Escolher na hora</option>
                                    {paymentAccounts.map((a) => (
                                        <option key={a.id} value={a.id}>
                                            {a.name}
                                        </option>
                                    ))}
                                </select>
                                <FieldError
                                    message={errors.payment_account_id}
                                />
                            </div>
                        )}
                    </div>
                )}

                {isEditing && account && (
                    <div className="rounded-2xl border border-[#E8C4C0] p-4">
                        <p className="font-serif text-[#A65D57]">
                            Zona de perigo
                        </p>
                        <p className="mt-1 mb-3 text-sm text-[#8B7355]">
                            Excluir apaga {isCard ? 'o cartão' : 'a conta'} e
                            todos os lançamentos dele{isCard ? '' : 'a'}. Você
                            vê exatamente o que será apagado antes de confirmar.
                        </p>
                        <button
                            type="button"
                            onClick={() => setDeleting(true)}
                            className="inline-flex items-center gap-2 rounded-xl border-2 border-[#A65D57] px-4 py-2 text-sm font-bold text-[#A65D57] transition-colors hover:bg-[#A65D57] hover:text-white"
                        >
                            <Trash2 className="h-4 w-4" />
                            Excluir {isCard ? 'cartão' : 'conta'}
                        </button>
                        <DeleteAccountModal
                            account={account}
                            isOpen={deleting}
                            onClose={() => setDeleting(false)}
                            onDeleted={onClose}
                        />
                    </div>
                )}
            </div>

            <div className="border-t border-[#E8DCC4] bg-[#F5EFE6] p-6">
                <button
                    type="submit"
                    disabled={form.processing || !data.name}
                    className="w-full rounded-xl bg-[#8B7355] py-4 text-lg font-medium text-[#F5EFE6] shadow-lg transition-colors hover:bg-[#6B4E3D] disabled:cursor-not-allowed disabled:opacity-50"
                >
                    {isEditing
                        ? 'Salvar alterações'
                        : isCard
                          ? 'Criar cartão'
                          : 'Criar conta'}
                </button>
            </div>
        </Form>
    );
}
