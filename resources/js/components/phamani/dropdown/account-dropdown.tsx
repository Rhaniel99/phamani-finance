import { ChevronDown, Wallet } from 'lucide-react';
import {
    DropdownMenu,
    DropdownMenuContent,
    DropdownMenuItem,
    DropdownMenuSeparator,
    DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import type { Account } from '@/types/phamani';

interface AccountDropdownProps {
    value: Account | null;
    accounts: Account[];
    onChange: (account: Account) => void;
    onCreate: () => void;
}

export function AccountDropdown({
    value,
    accounts,
    onChange,
    onCreate,
}: AccountDropdownProps) {
    return (
        <DropdownMenu>
            <DropdownMenuTrigger asChild>
                <button
                    type="button"
                    className="flex w-full items-center justify-between rounded-xl border-2 border-[#E8DCC4] bg-white px-4 py-3 transition-colors hover:border-[#6B4E3D]"
                >
                    {value ? (
                        <div className="flex min-w-0 items-center gap-3">
                            <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-[#E8DCC4]">
                                <Wallet className="h-4 w-4 text-[#6B4E3D]" />
                            </div>
                            <span className="truncate text-[#3D2817]">
                                {value.name}
                            </span>
                        </div>
                    ) : (
                        <span className="text-[#8B7355]">Conta</span>
                    )}
                    <ChevronDown className="h-4 w-4 shrink-0 text-[#8B7355]" />
                </button>
            </DropdownMenuTrigger>

            <DropdownMenuContent
                side="bottom"
                align="start"
                sideOffset={8}
                className="z-[9999] w-(--radix-dropdown-menu-trigger-width) rounded-xl border border-[#E8DCC4] bg-[#F5EFE6] shadow-xl"
            >
                {accounts.map((acc) => (
                    <DropdownMenuItem
                        key={acc.id}
                        onSelect={() => onChange(acc)}
                        className="flex cursor-pointer items-center gap-3"
                    >
                        <div className="flex h-7 w-7 items-center justify-center rounded-lg bg-[#E8DCC4]">
                            <Wallet className="h-4 w-4 text-[#6B4E3D]" />
                        </div>
                        <span>{acc.name}</span>
                    </DropdownMenuItem>
                ))}

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
