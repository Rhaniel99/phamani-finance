import { router } from '@inertiajs/react';
import { Link2, Link2Off, Mail, Plus, Pencil, Trash2 } from 'lucide-react';
import { useState } from 'react';
import {
    Dialog,
    DialogContent,
    DialogDescription,
    DialogHeader,
    DialogTitle,
} from '@/components/ui/dialog';
import { ContactAvatar } from '@/components/phamani/contact-avatar';
import { useContacts } from '@/hooks/use-contacts';
import {
    destroy as destroyContact,
    invite as inviteContact,
    store as storeContact,
    unlink as unlinkContact,
    update as updateContact,
} from '@/routes/contacts';
import type { Contact } from '@/types/phamani';

interface ContactsModalProps {
    open: boolean;
    onOpenChange: (open: boolean) => void;
}

/** Pessoas com quem você divide contas (não precisam usar o Phamani). */
export function ContactsModal({ open, onOpenChange }: ContactsModalProps) {
    const contacts = useContacts();
    const [name, setName] = useState('');
    const [busy, setBusy] = useState(false);

    function add() {
        const value = name.trim();
        if (!value) return;

        router.post(
            storeContact.url(),
            { name: value },
            {
                preserveState: true,
                preserveScroll: true,
                onStart: () => setBusy(true),
                onFinish: () => setBusy(false),
                onSuccess: () => setName(''),
            },
        );
    }

    function remove(id: string) {
        router.delete(destroyContact.url(id), {
            preserveState: true,
            preserveScroll: true,
        });
    }

    return (
        <Dialog open={open} onOpenChange={onOpenChange}>
            <DialogContent
                onOpenAutoFocus={(e) => e.preventDefault()}
                className="max-w-md overflow-hidden border-[#E8DCC4] bg-[#F5EFE6] p-0"
            >
                <DialogHeader className="border-b border-[#E8DCC4] px-6 pt-6 pb-4">
                    <DialogTitle className="text-xl text-[#3D2817]">
                        Contatos
                    </DialogTitle>
                    <DialogDescription className="mt-1 text-sm text-[#8B7355]">
                        Pessoas com quem você divide contas. Elas não precisam
                        usar o Phamani; se usarem, convide pelo e-mail do Google
                        e as divisões passam a aparecer para elas também.
                    </DialogDescription>
                </DialogHeader>

                <div className="space-y-4 px-6 py-4">
                    <div className="flex gap-2">
                        <label htmlFor="contact-name" className="sr-only">
                            Nome do contato
                        </label>
                        <input
                            id="contact-name"
                            value={name}
                            onChange={(e) => setName(e.target.value)}
                            onKeyDown={(e) => {
                                if (e.key === 'Enter') {
                                    e.preventDefault();
                                    add();
                                }
                            }}
                            placeholder="Nome (ex.: Mozi)"
                            className="w-full rounded-xl border-2 border-[#E8DCC4] bg-white px-4 py-2 text-[#3D2817] focus:border-[#6B4E3D] focus:outline-none"
                        />
                        <button
                            type="button"
                            onClick={add}
                            disabled={busy || !name.trim()}
                            aria-label="Adicionar contato"
                            className="shrink-0 rounded-xl bg-[#3D2817] px-3 text-[#F5EFE6] hover:bg-[#543924] disabled:opacity-40"
                        >
                            <Plus className="h-5 w-5" />
                        </button>
                    </div>

                    <ul className="max-h-[50vh] space-y-2 overflow-y-auto">
                        {contacts.length === 0 && (
                            <li className="rounded-2xl border border-dashed border-[#D4C5A9] p-4 text-center text-sm text-[#8B7355]">
                                Nenhum contato ainda.
                            </li>
                        )}
                        {contacts.map((c) => (
                            <ContactRow
                                key={c.id}
                                contact={c}
                                onRemove={() => remove(c.id)}
                            />
                        ))}
                    </ul>
                </div>
            </DialogContent>
        </Dialog>
    );
}

function ContactRow({
    contact,
    onRemove,
}: {
    contact: Contact;
    onRemove: () => void;
}) {
    const [inviting, setInviting] = useState(false);
    const [renaming, setRenaming] = useState(false);
    const [newName, setNewName] = useState(contact.name);
    const [email, setEmail] = useState('');
    const [busy, setBusy] = useState(false);

    function sendInvite() {
        const value = email.trim();
        if (!value) return;

        router.post(
            inviteContact.url(contact.id),
            { email: value },
            {
                preserveState: true,
                preserveScroll: true,
                onStart: () => setBusy(true),
                onFinish: () => setBusy(false),
                onSuccess: () => {
                    setEmail('');
                    setInviting(false);
                },
            },
        );
    }

    function rename() {
        const value = newName.trim();
        if (!value || value === contact.name) {
            setRenaming(false);
            return;
        }

        router.put(
            updateContact.url(contact.id),
            { name: value },
            {
                preserveState: true,
                preserveScroll: true,
                onSuccess: () => setRenaming(false),
            },
        );
    }

    function unlink() {
        router.post(
            unlinkContact.url(contact.id),
            {},
            { preserveState: true, preserveScroll: true },
        );
    }

    return (
        <li className="rounded-2xl border border-[#E8DCC4] bg-white px-4 py-3">
            <div className="flex items-center justify-between gap-2">
                <span className="flex min-w-0 items-center gap-3 text-sm font-medium text-[#3D2817]">
                    <ContactAvatar
                        name={contact.linked_user?.name ?? contact.name}
                        avatar={contact.linked_user?.avatar}
                        className="h-9 w-9"
                    />
                    <span className="min-w-0">
                        {renaming ? (
                            <input
                                aria-label={`Novo nome para ${contact.name}`}
                                autoFocus
                                value={newName}
                                onChange={(e) => setNewName(e.target.value)}
                                onBlur={rename}
                                onKeyDown={(e) => {
                                    if (e.key === 'Enter') {
                                        e.preventDefault();
                                        rename();
                                    }
                                    if (e.key === 'Escape') {
                                        setNewName(contact.name);
                                        setRenaming(false);
                                    }
                                }}
                                className="w-full rounded-lg border-2 border-[#E8DCC4] px-2 py-1 text-sm focus:border-[#6B4E3D] focus:outline-none"
                            />
                        ) : (
                            <span className="block truncate">
                                {contact.name}
                            </span>
                        )}
                        {contact.linked_user ? (
                            <span className="flex items-center gap-1 text-xs font-normal text-[#1F5428]">
                                <Link2 className="h-3 w-3" /> No Phamani como{' '}
                                {contact.linked_user.name}
                            </span>
                        ) : contact.pending_invite_email ? (
                            <span className="block truncate text-xs font-normal text-[#8B7355]">
                                Convite enviado para{' '}
                                {contact.pending_invite_email}
                            </span>
                        ) : null}
                    </span>
                </span>

                <div className="flex shrink-0 items-center gap-1">
                    <button
                        type="button"
                        onClick={() => setRenaming(true)}
                        aria-label={`Renomear ${contact.name}`}
                        title="Renomear"
                        className="rounded-lg p-2 text-[#8B7355] hover:bg-[#E8DCC4]"
                    >
                        <Pencil className="h-4 w-4" />
                    </button>
                    {contact.linked_user ? (
                        <button
                            type="button"
                            onClick={unlink}
                            aria-label={`Desvincular ${contact.name}`}
                            title="Desvincular"
                            className="rounded-lg p-2 text-[#8B7355] hover:bg-[#E8DCC4]"
                        >
                            <Link2Off className="h-4 w-4" />
                        </button>
                    ) : (
                        <button
                            type="button"
                            onClick={() => setInviting((v) => !v)}
                            aria-label={`Convidar ${contact.name}`}
                            title="Convidar para o Phamani"
                            className="rounded-lg p-2 text-[#6B4E3D] hover:bg-[#E8DCC4]"
                        >
                            <Mail className="h-4 w-4" />
                        </button>
                    )}
                    <button
                        type="button"
                        onClick={onRemove}
                        aria-label={`Excluir ${contact.name}`}
                        className="rounded-lg p-2 text-[#8B7355] hover:bg-[#FCE7E7] hover:text-[#A65D57]"
                    >
                        <Trash2 className="h-4 w-4" />
                    </button>
                </div>
            </div>

            {inviting && !contact.linked_user && (
                <div className="mt-3 flex gap-2">
                    <label htmlFor={`invite-${contact.id}`} className="sr-only">
                        E-mail do Google de {contact.name}
                    </label>
                    <input
                        id={`invite-${contact.id}`}
                        type="email"
                        value={email}
                        onChange={(e) => setEmail(e.target.value)}
                        onKeyDown={(e) => {
                            if (e.key === 'Enter') {
                                e.preventDefault();
                                sendInvite();
                            }
                        }}
                        placeholder="E-mail do Google"
                        className="w-full rounded-xl border-2 border-[#E8DCC4] bg-white px-3 py-2 text-sm text-[#3D2817] focus:border-[#6B4E3D] focus:outline-none"
                    />
                    <button
                        type="button"
                        onClick={sendInvite}
                        disabled={busy || !email.trim()}
                        className="shrink-0 rounded-xl bg-[#3D2817] px-3 text-sm font-medium text-[#F5EFE6] hover:bg-[#543924] disabled:opacity-40"
                    >
                        Convidar
                    </button>
                </div>
            )}
        </li>
    );
}
