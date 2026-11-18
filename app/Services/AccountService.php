<?php

namespace App\Services;

use App\DTOs\Account\StoreAccountData;
use App\Interfaces\Repositories\IAccountRepository;
use App\Interfaces\Services\IAccountService;
use App\Models\Account;
use Illuminate\Database\Eloquent\Collection;

class AccountService implements IAccountService
{
    public function __construct(
        protected IAccountRepository $repository,
    ) {}

    public function listForUser(string $userId): Collection
    {
        return $this->repository
            ->query()
            ->where('user_id', $userId)
            ->orderByDesc('balance')
            ->get(['id', 'name', 'type', 'balance']);
    }

    public function create(string $userId, StoreAccountData $dto): Account
    {
        /** @var Account */
        return $this->repository->create([
            'user_id' => $userId,
            'name' => $dto->name,
            'type' => $dto->type,
            'balance' => 0,
        ]);
    }

    public function createDefaultForUser(string $userId): Account
    {
        /** @var Account */
        return $this->repository->query()->firstOrCreate(
            ['user_id' => $userId, 'name' => 'Carteira'],
            ['type' => 'cash', 'balance' => 0],
        );
    }
}
