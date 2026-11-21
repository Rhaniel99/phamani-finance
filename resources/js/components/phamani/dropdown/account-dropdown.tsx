import { Pencil } from 'lucide-react';
import { useState } from 'react';
import { AccountIcon } from '@/components/phamani/account-icon';
import { DropdownTrigger } from '@/components/phamani/dropdown/dropdown-trigger';
import {
    DropdownMenu,
    DropdownMenuContent,
    DropdownMenuItem,
    DropdownMenuLabel,
    DropdownMenuSeparator,
    DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { ACCOUNT_TYPE_LABELS, isCreditCard } from '@/types/phamani';
import type { Account } from '@/types/phamani';

interface AccountDropdownProps {
    value: Account | null;
    accounts: Account[];
    onChange: (account: Account) => void;
    onCreate: () => void;
    onEdit?: (account: Account) => void;
}

export function AccountDropdown({
    value,
    accounts,
    onChange,
    onCreate,
    onEdit,
}: AccountDropdownProps) {
    const [open, setOpen] = useState(false);
    const plain = accounts.filter((a) => !isCreditCard(a));
    const cards = accounts.filter(isCreditCard);

    function edit(account: Account) {
        setOpen(false);
        onEdit?.(account);
    }

    const renderItem = (acc: Account) => (
        <DropdownMenuItem
            key={acc.id}
            onSelect={() => onChange(acc)}
            className="group flex cursor-pointer items-center gap-3"
        >
            <AccountIcon type={acc.type} className="h-7 w-7" />
            <span className="min-w-0 flex-1">
                <span className="block truncate">{acc.name}</span>
                <span className="block text-[11px] text-[#8B7355]">
                    {ACCOUNT_TYPE_LABELS[acc.type]}
                </span>
            </span>
            {onEdit && (
                <button
                    type="button"
                    aria-label={`Editar ${acc.name}`}
                    title="Editar"
                    onClick={(e) => {
                        e.preventDefault();
                        e.stopPropagation();
                        edit(acc);
                    }}
                    className="rounded-md p-1.5 text-[#8B7355] opacity-60 group-hover:opacity-100 hover:bg-[#E8DCC4] hover:text-[#3D2817]"
                >
                    <Pencil className="h-3.5 w-3.5" />
                </button>
            )}
        </DropdownMenuItem>
    );

    return (
        <DropdownMenu open={open} onOpenChange={setOpen}>
            <DropdownMenuTrigger asChild>
                <DropdownTrigger
                    icon={value ? <AccountIcon type={value.type} /> : undefined}
                    title={value ? value.name : 'Conta'}
                    subtitle={
                        value ? ACCOUNT_TYPE_LABELS[value.type] : undefined
                    }
                    placeholder={!value}
                />
            </DropdownMenuTrigger>

            <DropdownMenuContent
                side="bottom"
                align="start"
                sideOffset={8}
                className="z-[9999] max-h-80 w-(--radix-dropdown-menu-trigger-width) min-w-64 overflow-y-auto rounded-xl border border-[#E8DCC4] bg-[#F5EFE6] shadow-xl"
            >
                {plain.length > 0 && (
                    <DropdownMenuLabel className="text-[10px] font-bold tracking-wide text-[#8B7355] uppercase">
                        Contas
                    </DropdownMenuLabel>
                )}
                {plain.map(renderItem)}

                {cards.length > 0 && (
                    <>
                        {plain.length > 0 && <DropdownMenuSeparator />}
                        <DropdownMenuLabel className="text-[10px] font-bold tracking-wide text-[#8B7355] uppercase">
                            Cartões de crédito
                        </DropdownMenuLabel>
                        {cards.map(renderItem)}
                    </>
                )}

                <DropdownMenuSeparator />

                <DropdownMenuItem
                    onSelect={onCreate}
                    className="cursor-pointer font-medium text-[#6B4E3D]"
                >
                    + Criar nova conta
                </DropdownMenuItem>
            </DropdownMenuContent>
        </DropdownMenu>
    );
}
