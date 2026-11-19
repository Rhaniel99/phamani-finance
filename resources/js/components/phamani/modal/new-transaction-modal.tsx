import { AnimatePresence } from 'motion/react';
import { TransactionModalLayout } from '@/components/phamani/modal/transaction-modal-layout';
import type { Account, Category, Transaction } from '@/types/phamani';

interface NewTransactionModalProps {
    isOpen: boolean;
    onClose: () => void;
    categories: Category[];
    accounts: Account[];
    /** Quando informado, abre o modal em modo de edição. */
    transaction?: Transaction | null;
    /** Conta pré-selecionada numa nova transação. */
    defaultAccountId?: string;
}

export function NewTransactionModal({
    isOpen,
    onClose,
    categories,
    accounts,
    transaction,
    defaultAccountId,
}: NewTransactionModalProps) {
    return (
        <AnimatePresence>
            {isOpen && (
                <TransactionModalLayout
                    // key garante um formulário novo a cada transação editada
                    key={transaction?.id ?? 'new'}
                    onClose={onClose}
                    categories={categories}
                    accounts={accounts}
                    transaction={transaction}
                    defaultAccountId={defaultAccountId}
                />
            )}
        </AnimatePresence>
    );
}
