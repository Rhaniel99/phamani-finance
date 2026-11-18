import { Banknote, CreditCard, PiggyBank, Wallet } from 'lucide-react';
import type { ElementType } from 'react';
import { Form } from '@/components/form';
import { DrawerShell } from '@/components/phamani/drawer/drawer-shell';
import { Label } from '@/components/ui/label';
import { useAccountsForm } from '@/hooks/use-accounts-form';
import { cn } from '@/lib/utils';
import type { CreateAccount } from '@/types/phamani';

interface CreateAccountDrawerProps {
    isOpen: boolean;
    onClose: () => void;
}

const TYPES: Array<{
    value: CreateAccount['type'];
    label: string;
    icon: ElementType;
}> = [
    { value: 'cash', label: 'Dinheiro', icon: Banknote },
    { value: 'checking', label: 'Conta', icon: Wallet },
    { value: 'savings', label: 'Poupança', icon: PiggyBank },
    { value: 'credit', label: 'Crédito', icon: CreditCard },
];

export function CreateAccountDrawer({
    isOpen,
    onClose,
}: CreateAccountDrawerProps) {
    const { form, submit } = useAccountsForm(onClose);

    return (
        <DrawerShell isOpen={isOpen} onClose={onClose} title="Nova Conta">
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
                            Nome da conta
                        </Label>
                        <input
                            id="account-name"
                            value={form.data.name}
                            onChange={(e) =>
                                form.setData('name', e.target.value)
                            }
                            placeholder="Ex: Nubank"
                            className="w-full rounded-xl border-2 border-[#E8DCC4] bg-white px-4 py-3 text-[#3D2817] placeholder:text-[#D4C5A9] focus:border-[#6B4E3D] focus:outline-none"
                        />
                        {form.errors.name && (
                            <p className="text-xs text-[#D4183D]">
                                {form.errors.name}
                            </p>
                        )}
                    </div>

                    <div className="space-y-3">
                        <Label className="font-serif text-[#6B4E3D]">
                            Tipo
                        </Label>
                        <div className="grid grid-cols-2 gap-3">
                            {TYPES.map(({ value, label, icon: Icon }) => (
                                <button
                                    key={value}
                                    type="button"
                                    onClick={() => form.setData('type', value)}
                                    className={cn(
                                        'flex flex-col items-center justify-center gap-2 rounded-xl border-2 p-4 transition-all',
                                        form.data.type === value
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
                </div>

                <div className="border-t border-[#E8DCC4] bg-[#F5EFE6] p-6">
                    <button
                        type="submit"
                        disabled={form.processing || !form.data.name}
                        className="w-full rounded-xl bg-[#8B7355] py-4 text-lg font-medium text-[#F5EFE6] shadow-lg transition-colors hover:bg-[#6B4E3D] disabled:cursor-not-allowed disabled:opacity-50"
                    >
                        Criar conta
                    </button>
                </div>
            </Form>
        </DrawerShell>
    );
}
