import { X } from 'lucide-react';
import { AnimatePresence, motion } from 'motion/react';
import type { ReactNode } from 'react';
import { cn } from '@/lib/utils';

interface DrawerShellProps {
    isOpen: boolean;
    onClose: () => void;
    title: string;
    side?: 'left' | 'right';
    children: ReactNode;
}

/** Painel lateral com overlay próprio (fica por cima do modal de transação). */
export function DrawerShell({
    isOpen,
    onClose,
    title,
    side = 'right',
    children,
}: DrawerShellProps) {
    const offscreen = side === 'right' ? '100%' : '-100%';

    return (
        <AnimatePresence>
            {isOpen && (
                <>
                    <motion.div
                        initial={{ opacity: 0 }}
                        animate={{ opacity: 1 }}
                        exit={{ opacity: 0 }}
                        onClick={onClose}
                        className="fixed inset-0 z-[80] cursor-default bg-[#3D2817]/40 backdrop-blur-[2px]"
                    />

                    <motion.div
                        role="dialog"
                        aria-modal="true"
                        aria-label={title}
                        initial={{ x: offscreen }}
                        animate={{ x: 0 }}
                        exit={{ x: offscreen }}
                        transition={{
                            type: 'spring',
                            damping: 25,
                            stiffness: 200,
                        }}
                        className={cn(
                            'fixed top-0 z-[90] flex h-full w-full max-w-[400px] flex-col bg-[#F5EFE6] shadow-2xl',
                            side === 'right'
                                ? 'right-0 border-l-2 border-[#E8DCC4]'
                                : 'left-0 border-r border-[#E8DCC4]',
                        )}
                    >
                        <div className="flex items-center justify-between border-b border-[#E8DCC4] p-6">
                            <h2 className="text-xl font-bold text-[#3D2817]">
                                {title}
                            </h2>
                            <button
                                type="button"
                                onClick={onClose}
                                aria-label="Fechar"
                                className="rounded-xl p-2 text-[#6B4E3D] transition-colors hover:bg-[#E8DCC4] hover:text-[#3D2817]"
                            >
                                <X className="h-6 w-6" />
                            </button>
                        </div>

                        {children}
                    </motion.div>
                </>
            )}
        </AnimatePresence>
    );
}
