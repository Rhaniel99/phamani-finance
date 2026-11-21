import { Pencil } from 'lucide-react';
import { AccountIcon } from '@/components/phamani/account-icon';
import {
    Dialog,
    DialogContent,
    DialogDescription,
    DialogHeader,
    DialogTitle,
} from '@/components/ui/dialog';
import { formatCurrency } from '@/lib/format';
import { ACCOUNT_TYPE_LABELS, isCreditCard } from '@/types/phamani';
import type { Account } from '@/types/phamani';

interface AccountsListModalProps {
    open: boolean;
    onOpenChange: (open: boolean) => void;
    accounts: Account[];
    onEdit?: (account: Account) => void;
}

export function AccountsListModal({
    open,
    onOpenChange,
    accounts,
    onEdit,
}: AccountsListModalProps) {
    // Cartão é dívida (fatura), não entra no saldo.
    const totalBalance = accounts
        .filter((acc) => !isCreditCard(acc))
        .reduce((sum, acc) => sum + Number(acc.balance), 0);

    return (
        <Dialog open={open} onOpenChange={onOpenChange}>
            <DialogContent
                onOpenAutoFocus={(e) => e.preventDefault()}
                className="max-w-lg overflow-hidden border-[#E8DCC4] bg-[#F5EFE6] p-0"
            >
                <DialogHeader className="border-b border-[#E8DCC4] px-6 pt-6 pb-4">
                    <DialogTitle className="text-xl text-[#3D2817]">
                        Minhas Contas
                    </DialogTitle>
                    <DialogDescription className="mt-1 text-sm text-[#8B7355]">
                        {accounts.length}{' '}
                        {accounts.length === 1 ? 'conta' : 'contas'} · Saldo
                        total{' '}
                        <span className="font-semibold text-[#3D2817]">
                            {formatCurrency(totalBalance)}
                        </span>
                    </DialogDescription>
                </DialogHeader>

                <div className="max-h-[65vh] space-y-3 overflow-y-auto px-4 py-4">
                    {accounts.map((account) => (
                        <div
                            key={account.id}
                            className="flex items-center justify-between rounded-2xl border border-[#E8DCC4] bg-white p-4 transition-colors hover:bg-[#E8DCC4]/40"
                        >
                            <div className="flex items-center gap-3">
                                <AccountIcon
                                    type={account.type}
                                    className="h-10 w-10 rounded-xl"
                                />
                                <div>
                                    <p className="text-sm font-semibold text-[#3D2817]">
                                        {account.name}
                                    </p>
                                    <p className="text-xs text-[#8B7355]">
                                        {ACCOUNT_TYPE_LABELS[account.type]}
                                    </p>
                                </div>
                                {onEdit && (
                                    <button
                                        type="button"
                                        aria-label={`Editar ${account.name}`}
                                        title="Editar"
                                        onClick={() => onEdit(account)}
                                        className="rounded-md p-1.5 text-[#8B7355] hover:bg-[#E8DCC4] hover:text-[#3D2817]"
                                    >
                                        <Pencil className="h-3.5 w-3.5" />
                                    </button>
                                )}
                            </div>

                            {isCreditCard(account) ? (
                                <div className="text-right">
                                    <p className="text-[10px] text-[#8B7355] uppercase">
                                        Disponível
                                    </p>
                                    <p className="text-sm font-bold text-[#3D2817]">
                                        {account.card?.available != null
                                            ? formatCurrency(
                                                  account.card.available,
                                              )
                                            : '—'}
                                    </p>
                                </div>
                            ) : (
                                <div className="text-right">
                                    <p className="text-[10px] text-[#8B7355] uppercase">
                                        Saldo
                                    </p>
                                    <p
                                        className={`text-sm font-bold ${Number(account.balance) < 0 ? 'text-[#B91C1C]' : 'text-[#3D2817]'}`}
                                    >
                                        {formatCurrency(account.balance)}
                                    </p>
                                </div>
                            )}
                        </div>
                    ))}
                </div>
            </DialogContent>
        </Dialog>
    );
}
