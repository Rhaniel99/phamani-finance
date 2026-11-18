import { X } from 'lucide-react';
import { motion } from 'motion/react';
import { useEffect, useState } from 'react';
import { CreateAccountDrawer } from '@/components/phamani/drawer/create-account-drawer';
import { CreateCategoryDrawer } from '@/components/phamani/drawer/create-category-drawer';
import { TransactionForm } from '@/components/phamani/modal/transaction-form';
import { TransactionPreview } from '@/components/phamani/modal/transaction-preview';
import { useTransactionForm } from '@/hooks/use-transaction-form';
import type { Account, Category, Transaction } from '@/types/phamani';

interface TransactionModalLayoutProps {
    onClose: () => void;
    categories: Category[];
    accounts: Account[];
    /** Quando informado, o modal edita esta transação. */
    transaction?: Transaction | null;
}

export function TransactionModalLayout({
    onClose,
    categories,
    accounts,
    transaction,
}: TransactionModalLayoutProps) {
    const [accountDrawerOpen, setAccountDrawerOpen] = useState(false);
    const [categoryDrawerOpen, setCategoryDrawerOpen] = useState(false);

    const { form, submit, isEditing } = useTransactionForm(
        transaction,
        onClose,
    );

    // Fecha com ESC (quando nenhum drawer estiver aberto)
    useEffect(() => {
        const onKey = (e: KeyboardEvent) => {
            if (e.key === 'Escape' && !accountDrawerOpen && !categoryDrawerOpen)
                onClose();
        };

        window.addEventListener('keydown', onKey);

        return () => window.removeEventListener('keydown', onKey);
    }, [accountDrawerOpen, categoryDrawerOpen, onClose]);

    return (
        <>
            <div className="fixed inset-0 z-[60] flex items-center justify-center bg-[#3D2817]/60 p-4 backdrop-blur-sm">
                <motion.div
                    role="dialog"
                    aria-modal="true"
                    aria-label={
                        isEditing ? 'Editar transação' : 'Nova transação'
                    }
                    initial={{ opacity: 0, scale: 0.95 }}
                    animate={{ opacity: 1, scale: 1 }}
                    exit={{ opacity: 0, scale: 0.95 }}
                    className="relative flex h-[85vh] w-full max-w-5xl flex-col overflow-hidden rounded-[2rem] border-2 border-[#E8DCC4] bg-[#F5EFE6] shadow-2xl md:flex-row"
                >
                    <button
                        type="button"
                        onClick={onClose}
                        aria-label="Fechar"
                        className="absolute top-6 right-6 z-20 text-[#6B4E3D] hover:text-[#3D2817]"
                    >
                        <X className="h-6 w-6" />
                    </button>

                    <TransactionForm
                        form={form}
                        categories={categories}
                        accounts={accounts}
                        onSubmit={submit}
                        isEditing={isEditing}
                        onCreateCategory={() => setCategoryDrawerOpen(true)}
                        onCreateAccount={() => setAccountDrawerOpen(true)}
                    />

                    <TransactionPreview
                        data={form.data}
                        categories={categories}
                        accounts={accounts}
                    />
                </motion.div>
            </div>

            <CreateAccountDrawer
                isOpen={accountDrawerOpen}
                onClose={() => setAccountDrawerOpen(false)}
            />
            <CreateCategoryDrawer
                isOpen={categoryDrawerOpen}
                onClose={() => setCategoryDrawerOpen(false)}
            />
        </>
    );
}
