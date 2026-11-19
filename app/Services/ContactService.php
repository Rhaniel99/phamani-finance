<?php

namespace App\Services;

use App\DTOs\Contact\StoreContactData;
use App\DTOs\Contact\UpdateContactData;
use App\Interfaces\Repositories\IContactRepository;
use App\Interfaces\Services\IContactService;
use App\Models\Contact;
use App\Models\ContactInvitation;
use App\Models\Transaction;
use App\Models\TransactionSplit;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Validation\ValidationException;

class ContactService implements IContactService
{
    public function __construct(
        protected IContactRepository $repository,
    ) {}

    public function listForUser(string $userId): Collection
    {
        $contacts = $this->repository
            ->query()
            ->with('linkedUser:id,name,email,avatar')
            ->where('user_id', $userId)
            ->orderBy('name')
            ->get(['id', 'name', 'linked_user_id']);

        // E-mail do convite pendente de cada contato (para mostrar "convite enviado").
        $pending = ContactInvitation::query()
            ->whereIn('contact_id', $contacts->pluck('id'))
            ->where('status', 'pending')
            ->pluck('email', 'contact_id');

        return $contacts->each(fn (Contact $c) => $c->setAttribute('pending_invite_email', $pending[$c->id] ?? null));
    }

    public function create(string $userId, StoreContactData $dto): Contact
    {
        /** @var Contact */
        return $this->repository->create([
            'user_id' => $userId,
            'name' => trim($dto->name),
        ]);
    }

    public function rename(Contact $contact, UpdateContactData $dto): Contact
    {
        $contact->update(['name' => trim($dto->name)]);

        return $contact;
    }

    public function delete(Contact $contact): void
    {
        $inUse = TransactionSplit::query()->where('contact_id', $contact->id)->exists()
            || Transaction::query()->where('paid_by_contact_id', $contact->id)->exists();

        if ($inUse) {
            throw ValidationException::withMessages([
                'contact' => "{$contact->name} está em divisões já lançadas e não pode ser excluído.",
            ]);
        }

        $this->repository->delete($contact->id);
    }
}
