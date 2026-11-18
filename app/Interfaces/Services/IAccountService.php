<?php

namespace App\Interfaces\Services;

use App\DTOs\Account\StoreAccountData;
use App\Models\Account;
use Illuminate\Database\Eloquent\Collection;

interface IAccountService
{
    public function listForUser(string $userId): Collection;

    public function create(string $userId, StoreAccountData $dto): Account;

    /**
     * Cria a conta padrão ("Carteira") de um usuário recém-cadastrado.
     */
    public function createDefaultForUser(string $userId): Account;
}
