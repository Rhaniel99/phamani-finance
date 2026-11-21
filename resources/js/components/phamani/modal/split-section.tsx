import { router } from '@inertiajs/react';
import { Check, HandCoins, Plus, Users } from 'lucide-react';
import { useState } from 'react';
import { ContactAvatar } from '@/components/phamani/contact-avatar';
import { ToggleField } from '@/components/toggle-field';
import { useContacts } from '@/hooks/use-contacts';
import { formatCurrency } from '@/lib/format';
import { cn } from '@/lib/utils';
import { store as storeContact } from '@/routes/contacts';
import type { Contact, SplitForm, SplitParticipantForm } from '@/types/phamani';

interface SplitSectionProps {
    split: SplitForm | null;
    onChange: (split: SplitForm | null) => void;
    /** Valor digitado no formulário (total, ou da parcela). */
    amount: number;
    errors: Partial<Record<string, string>>;
}

const labelClass = 'mb-2 ml-1 block font-serif text-sm text-[#6B4E3D]';
const smallInput =
    'w-full rounded-xl border-2 border-[#E8DCC4] bg-white px-3 py-2 text-[#3D2817] focus:border-[#6B4E3D] focus:outline-none';

const EMPTY_SPLIT: SplitForm = {
    mode: 'equal',
    participants: [{ contact_id: null, amount: '' }],
    paid_by_contact_id: null,
};

export function SplitSection({
    split,
    onChange,
    amount,
    errors,
}: SplitSectionProps) {
    const contacts = useContacts();
    const [newName, setNewName] = useState('');
    const [adding, setAdding] = useState(false);

    const selectedIds = (split?.participants ?? [])
        .map((p) => p.contact_id)
        .filter((id): id is string => id !== null);
    // Desmarcar "Você" = compra para outra pessoa (sua parte é zero, o resto fica a receber).
    const includeMe = split?.include_me !== false;
    const people = selectedIds.length + (includeMe ? 1 : 0);
    const nameOf = (id: string | null) =>
        id === null ? 'Você' : (contacts.find((c) => c.id === id)?.name ?? '—');

    function update(patch: Partial<SplitForm>) {
        if (split) onChange({ ...split, ...patch });
    }

    function toggleMe() {
        if (!split) return;

        onChange(
            includeMe
                ? {
                      ...split,
                      include_me: false,
                      participants: split.participants.filter(
                          (p) => p.contact_id !== null,
                      ),
                      // Numa compra para outra pessoa, quem pagou é você.
                      paid_by_contact_id: null,
                  }
                : {
                      ...split,
                      include_me: true,
                      participants: [
                          { contact_id: null, amount: '' },
                          ...split.participants,
                      ],
                  },
        );
    }

    function toggleContact(contact: Contact) {
        if (!split) return;

        const isIn = selectedIds.includes(contact.id);
        const participants: SplitParticipantForm[] = isIn
            ? split.participants.filter((p) => p.contact_id !== contact.id)
            : [...split.participants, { contact_id: contact.id, amount: '' }];

        onChange({
            ...split,
            participants,
            // Quem pagou precisa estar na divisão.
            paid_by_contact_id:
                isIn && split.paid_by_contact_id === contact.id
                    ? null
                    : split.paid_by_contact_id,
        });
    }

    function setParticipantAmount(
        contactId: string | null,
        value: number | '',
    ) {
        if (!split) return;

        update({
            participants: split.participants.map((p) =>
                p.contact_id === contactId ? { ...p, amount: value } : p,
            ),
        });
    }

    function addContact() {
        const name = newName.trim();
        if (!name) return;

        router.post(
            storeContact.url(),
            { name },
            {
                preserveState: true,
                preserveScroll: true,
                only: ['contacts', 'errors'],
                onStart: () => setAdding(true),
                onFinish: () => setAdding(false),
                onSuccess: (page) => {
                    setNewName('');
                    const created = (
                        page.props.contacts as Contact[] | undefined
                    )?.find((c) => c.name === name);
                    if (created && split) {
                        onChange({
                            ...split,
                            participants: [
                                ...split.participants,
                                { contact_id: created.id, amount: '' },
                            ],
                        });
                    }
                },
            },
        );
    }

    const customSum = (split?.participants ?? []).reduce(
        (sum, p) => sum + Number(p.amount || 0),
        0,
    );
    const customDiff = Math.round((amount - customSum) * 100) / 100;

    return (
        <div className="space-y-4">
            <ToggleField
                label="Dividir com alguém?"
                icon={<Users className="h-5 w-5" />}
                active={!!split}
                onToggle={() => onChange(split ? null : { ...EMPTY_SPLIT })}
            />

            {split && (
                <div className="space-y-5 border-l-2 border-[#6B4E3D] pl-4">
                    {/* Participantes */}
                    <div>
                        <span className={labelClass}>Dividir entre</span>
                        <div className="flex flex-wrap gap-2">
                            <button
                                type="button"
                                onClick={toggleMe}
                                aria-pressed={includeMe}
                                title={
                                    includeMe
                                        ? 'Desmarque se a compra foi só para outra pessoa'
                                        : 'Incluir você na divisão'
                                }
                                className={cn(
                                    'inline-flex items-center gap-1 rounded-full border px-3 py-1.5 text-sm font-medium transition-colors',
                                    includeMe
                                        ? 'border-[#3D2817] bg-[#3D2817] text-[#F5EFE6]'
                                        : 'border-[#D4C5A9] bg-white text-[#6B4E3D] hover:border-[#6B4E3D]',
                                )}
                            >
                                {includeMe && <Check className="h-3.5 w-3.5" />}
                                Você
                            </button>
                            {contacts.map((c) => {
                                const active = selectedIds.includes(c.id);
                                return (
                                    <button
                                        key={c.id}
                                        type="button"
                                        onClick={() => toggleContact(c)}
                                        aria-pressed={active}
                                        className={cn(
                                            'inline-flex items-center gap-1 rounded-full border px-3 py-1.5 text-sm font-medium transition-colors',
                                            active
                                                ? 'border-[#3D2817] bg-[#3D2817] text-[#F5EFE6]'
                                                : 'border-[#D4C5A9] bg-white text-[#6B4E3D] hover:border-[#6B4E3D]',
                                        )}
                                    >
                                        {active ? (
                                            <Check className="h-3.5 w-3.5" />
                                        ) : (
                                            <ContactAvatar
                                                name={c.name}
                                                avatar={c.linked_user?.avatar}
                                                className="h-5 w-5 text-[10px]"
                                            />
                                        )}
                                        {c.name}
                                    </button>
                                );
                            })}
                        </div>

                        <div className="mt-3 flex gap-2">
                            <label htmlFor="new-contact" className="sr-only">
                                Novo contato
                            </label>
                            <input
                                id="new-contact"
                                value={newName}
                                onChange={(e) => setNewName(e.target.value)}
                                onKeyDown={(e) => {
                                    if (e.key === 'Enter') {
                                        e.preventDefault();
                                        addContact();
                                    }
                                }}
                                placeholder="Novo contato (ex.: Mãe da Mozi)"
                                className={smallInput}
                            />
                            <button
                                type="button"
                                onClick={addContact}
                                disabled={adding || !newName.trim()}
                                aria-label="Adicionar contato"
                                className="shrink-0 rounded-xl bg-[#6B4E3D] px-3 text-[#F5EFE6] hover:bg-[#3D2817] disabled:opacity-40"
                            >
                                <Plus className="h-5 w-5" />
                            </button>
                        </div>
                        {errors['split.participants'] && (
                            <p className="mt-1 ml-1 text-xs text-[#D4183D]">
                                {errors['split.participants']}
                            </p>
                        )}
                        {errors.split && (
                            <p className="mt-1 ml-1 text-xs text-[#D4183D]">
                                {errors.split}
                            </p>
                        )}
                    </div>

                    {!includeMe && (
                        <div className="flex items-start gap-3 rounded-xl bg-[#FBF7F1] p-3 text-xs text-[#6B4E3D]">
                            <HandCoins className="mt-0.5 h-4 w-4 shrink-0 text-[#8B7355]" />
                            <span>
                                <strong className="text-[#3D2817]">
                                    Compra para outra pessoa.
                                </strong>{' '}
                                Você paga (o valor cheio sai da conta ou vai
                                para a fatura), mas não entra nas suas despesas:
                                fica <strong>a receber</strong> até a pessoa te
                                devolver.
                                {selectedIds.length === 0 &&
                                    ' Escolha para quem foi a compra.'}
                            </span>
                        </div>
                    )}

                    {selectedIds.length > 0 && (
                        <>
                            {/* Modo */}
                            <div className="flex rounded-xl bg-[#E8DCC4] p-1">
                                {(
                                    [
                                        ['equal', 'Partes iguais'],
                                        ['custom', 'Valores'],
                                    ] as const
                                ).map(([mode, label]) => (
                                    <button
                                        key={mode}
                                        type="button"
                                        onClick={() => update({ mode })}
                                        className={cn(
                                            'flex-1 rounded-lg py-2 text-sm font-bold transition-all',
                                            split.mode === mode
                                                ? 'bg-white text-[#3D2817] shadow-sm'
                                                : 'text-[#6B4E3D] hover:bg-[#D4C5A9]/50',
                                        )}
                                    >
                                        {label}
                                    </button>
                                ))}
                            </div>

                            {split.mode === 'equal' ? (
                                <div className="space-y-2">
                                    <p className="ml-1 text-sm text-[#6B4E3D]">
                                        {people === 1
                                            ? nameOf(selectedIds[0])
                                            : `${people} pessoas`}{' '}
                                        ·{' '}
                                        <strong>
                                            {formatCurrency(
                                                amount && people
                                                    ? amount / people
                                                    : 0,
                                            )}
                                        </strong>{' '}
                                        {people === 1
                                            ? 'a receber'
                                            : 'para cada'}
                                    </p>
                                    {includeMe && (
                                        <p className="ml-1 text-xs text-[#8B7355]">
                                            Só sabe a sua parte? Escolha “Minha
                                            parte” embaixo do campo Valor.
                                        </p>
                                    )}
                                </div>
                            ) : (
                                <div className="space-y-2">
                                    {split.participants.map((p) => (
                                        <div
                                            key={p.contact_id ?? 'me'}
                                            className="flex items-center gap-3"
                                        >
                                            <label
                                                htmlFor={`share-${p.contact_id ?? 'me'}`}
                                                className="w-28 shrink-0 truncate text-sm text-[#3D2817]"
                                            >
                                                {nameOf(p.contact_id)}
                                            </label>
                                            <input
                                                id={`share-${p.contact_id ?? 'me'}`}
                                                type="number"
                                                inputMode="decimal"
                                                step="0.01"
                                                min="0"
                                                value={p.amount}
                                                onChange={(e) =>
                                                    setParticipantAmount(
                                                        p.contact_id,
                                                        e.target.value === ''
                                                            ? ''
                                                            : Number(
                                                                  e.target
                                                                      .value,
                                                              ),
                                                    )
                                                }
                                                placeholder="0,00"
                                                className={smallInput}
                                            />
                                        </div>
                                    ))}
                                    <p
                                        className={cn(
                                            'ml-1 text-xs',
                                            customDiff === 0
                                                ? 'text-[#1F5428]'
                                                : 'text-[#A65D57]',
                                        )}
                                    >
                                        Soma {formatCurrency(customSum)} de{' '}
                                        {formatCurrency(amount)}
                                        {customDiff !== 0 &&
                                            ` · faltam ${formatCurrency(customDiff)}`}
                                    </p>
                                </div>
                            )}

                            {/* Quem pagou (numa compra para outra pessoa, é você) */}
                            {includeMe && (
                                <div>
                                    <label
                                        htmlFor="paid-by"
                                        className={labelClass}
                                    >
                                        Quem pagou?
                                    </label>
                                    <select
                                        id="paid-by"
                                        value={split.paid_by_contact_id ?? ''}
                                        onChange={(e) =>
                                            update({
                                                paid_by_contact_id:
                                                    e.target.value || null,
                                            })
                                        }
                                        className={smallInput}
                                    >
                                        <option value="">Você</option>
                                        {selectedIds.map((id) => (
                                            <option key={id} value={id}>
                                                {nameOf(id)}
                                            </option>
                                        ))}
                                    </select>
                                    {split.paid_by_contact_id && (
                                        <p className="mt-1 ml-1 text-xs text-[#8B7355]">
                                            Nenhuma conta sua é afetada: só a
                                            sua parte entra como despesa.
                                        </p>
                                    )}
                                    {errors['split.paid_by_contact_id'] && (
                                        <p className="mt-1 ml-1 text-xs text-[#D4183D]">
                                            {errors['split.paid_by_contact_id']}
                                        </p>
                                    )}
                                </div>
                            )}
                        </>
                    )}
                </div>
            )}
        </div>
    );
}
