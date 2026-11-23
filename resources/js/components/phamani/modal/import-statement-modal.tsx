import { useForm } from '@inertiajs/react';
import { FileText, ImageIcon, Upload, X } from 'lucide-react';
import { useRef, useState } from 'react';
import type { DragEvent } from 'react';
import { Button } from '@/components/phamani/ui/button';
import {
    Dialog,
    DialogContent,
    DialogDescription,
    DialogHeader,
    DialogTitle,
} from '@/components/ui/dialog';
import { cn } from '@/lib/utils';
import { store } from '@/routes/imports';

interface ImportStatementModalProps {
    cardId: string;
    isOpen: boolean;
    onClose: () => void;
}

const ACCEPT = 'application/pdf,image/png,image/jpeg,image/webp';

function formatSize(bytes: number): string {
    return bytes > 1024 * 1024
        ? `${(bytes / 1024 / 1024).toFixed(1).replace('.', ',')} MB`
        : `${Math.ceil(bytes / 1024)} KB`;
}

/**
 * Envio do extrato (PDF do app do Bradesco ou prints). O envio mostra o progresso do upload;
 * a leitura (OCR) acontece no servidor e é acompanhada na tela de revisão.
 */
export function ImportStatementModal({
    cardId,
    isOpen,
    onClose,
}: ImportStatementModalProps) {
    const input = useRef<HTMLInputElement>(null);
    const [dragging, setDragging] = useState(false);
    const form = useForm<{ files: File[] }>({ files: [] });

    function add(list: FileList | null) {
        if (!list) return;
        const files = [...form.data.files, ...Array.from(list)].slice(0, 10);
        form.setData('files', files);
        form.clearErrors();
    }

    function remove(index: number) {
        form.setData(
            'files',
            form.data.files.filter((_, i) => i !== index),
        );
    }

    function onDrop(e: DragEvent) {
        e.preventDefault();
        setDragging(false);
        add(e.dataTransfer.files);
    }

    function submit() {
        form.post(store.url(cardId), { forceFormData: true });
    }

    function close() {
        if (form.processing) return;
        form.reset();
        form.clearErrors();
        onClose();
    }

    const errors = Object.values(form.errors);
    const uploading = form.processing && form.progress;

    return (
        <Dialog open={isOpen} onOpenChange={(open) => !open && close()}>
            <DialogContent className="max-w-lg rounded-3xl border-[#E8DCC4] bg-[#F5EFE6]">
                <DialogHeader>
                    <DialogTitle className="text-2xl text-[#3D2817]">
                        Importar extrato
                    </DialogTitle>
                    <DialogDescription className="text-[#8B7355]">
                        Bradesco: no app, Cartões → Extrato → compartilhar em
                        PDF. Também vale print da tela. Nada é lançado antes da
                        sua revisão.
                    </DialogDescription>
                </DialogHeader>

                <button
                    type="button"
                    onClick={() => input.current?.click()}
                    onDragOver={(e) => {
                        e.preventDefault();
                        setDragging(true);
                    }}
                    onDragLeave={() => setDragging(false)}
                    onDrop={onDrop}
                    className={cn(
                        'flex flex-col items-center gap-2 rounded-2xl border-2 border-dashed p-8 text-center transition-colors',
                        dragging
                            ? 'border-[#3D2817] bg-[#E8DCC4]'
                            : 'border-[#D4C5A9] bg-white hover:border-[#6B4F3A]',
                    )}
                >
                    <Upload className="h-8 w-8 text-[#6B4E3D]" />
                    <span className="font-bold text-[#3D2817]">
                        Escolha ou arraste o arquivo
                    </span>
                    <span className="text-xs text-[#8B7355]">
                        PDF ou imagens · até 100 MB cada
                    </span>
                </button>
                <input
                    ref={input}
                    type="file"
                    accept={ACCEPT}
                    multiple
                    className="hidden"
                    onChange={(e) => {
                        add(e.target.files);
                        e.target.value = '';
                    }}
                />

                {form.data.files.length > 0 && (
                    <ul className="space-y-2">
                        {form.data.files.map((file, i) => (
                            <li
                                key={`${file.name}-${i}`}
                                className="flex items-center gap-3 rounded-xl border border-[#E8DCC4] bg-white px-3 py-2"
                            >
                                {file.type === 'application/pdf' ? (
                                    <FileText className="h-5 w-5 shrink-0 text-[#6B4E3D]" />
                                ) : (
                                    <ImageIcon className="h-5 w-5 shrink-0 text-[#6B4E3D]" />
                                )}
                                <span className="min-w-0 flex-1 truncate text-sm text-[#3D2817]">
                                    {file.name}
                                </span>
                                <span className="text-xs text-[#8B7355]">
                                    {formatSize(file.size)}
                                </span>
                                {!form.processing && (
                                    <button
                                        type="button"
                                        onClick={() => remove(i)}
                                        className="rounded-lg p-1 text-[#8B7355] hover:bg-[#F5EFE6]"
                                        aria-label={`Remover ${file.name}`}
                                    >
                                        <X className="h-4 w-4" />
                                    </button>
                                )}
                            </li>
                        ))}
                    </ul>
                )}

                {uploading && (
                    <div>
                        <div className="mb-1 flex justify-between text-xs font-bold text-[#6B4E3D]">
                            <span>Enviando…</span>
                            <span>{form.progress?.percentage ?? 0}%</span>
                        </div>
                        <div className="h-2 overflow-hidden rounded-full bg-[#E8DCC4]">
                            <div
                                className="h-full rounded-full bg-[#3D2817] transition-all"
                                style={{
                                    width: `${form.progress?.percentage ?? 0}%`,
                                }}
                            />
                        </div>
                    </div>
                )}

                {errors.length > 0 && (
                    <p className="text-sm text-[#A65D57]">{errors[0]}</p>
                )}

                <div className="flex justify-end gap-2">
                    <Button
                        variant="secondary"
                        onClick={close}
                        disabled={form.processing}
                    >
                        Cancelar
                    </Button>
                    <Button
                        onClick={submit}
                        disabled={
                            form.processing || form.data.files.length === 0
                        }
                    >
                        Ler extrato
                    </Button>
                </div>
            </DialogContent>
        </Dialog>
    );
}
