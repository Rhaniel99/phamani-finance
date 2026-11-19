<?php

namespace App\Interfaces\Services;

use App\DTOs\Contact\StoreContactData;
use App\DTOs\Contact\UpdateContactData;
use App\Models\Contact;
use Illuminate\Database\Eloquent\Collection;

interface IContactService
{
    public function listForUser(string $userId): Collection;

    public function create(string $userId, StoreContactData $dto): Contact;

    public function rename(Contact $contact, UpdateContactData $dto): Contact;

    /**
     * Exclui o contato, a não ser que ele já esteja em alguma divisão.
     */
    public function delete(Contact $contact): void;
}
