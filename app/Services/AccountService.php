<?php

namespace App\Services;

use App\DTOs\Account\StoreAccountData;
use App\DTOs\Account\UpdateAccountData;
use App\Interfaces\Repositories\IAccountRepository;
use App\Interfaces\Services\IAccountService;
use App\Interfaces\Services\ICreditCardService;
use App\Models\Account;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Support\Facades\DB;

class AccountService implements IAccountService
{
    public function __construct(
        protected IAccountRepository $repository,
        protected ICreditCardService $cards,
    ) {}

    public function listForUser(string $userId): Collection
    {
        /** @var Collection<int, Account> $accounts */
        $accounts = $this->repository
            ->query()
            ->where('user_id', $userId)
            ->orderByRaw("case when type = 'credit' then 1 else 0 end")
            ->orderByDesc('balance')
            ->get(['id', 'user_id', 'name', 'type', 'balance', 'credit_limit', 'closing_day', 'due_day', 'payment_account_id']);

        return $accounts->each(function (Account $account) {
            if ($account->isCreditCard()) {
                $account->setAttribute('card', $this->cards->summary($account));
            }
        });
    }

    public function create(string $userId, StoreAccountData $dto): Account
    {
        $isCard = $dto->type === 'credit';

        /** @var Account */
        return $this->repository->create([
            'user_id' => $userId,
            'name' => $dto->name,
            'type' => $dto->type,
            'balance' => 0,
            'credit_limit' => $isCard ? $dto->credit_limit : null,
            'closing_day' => $isCard ? $dto->closing_day : null,
            'due_day' => $isCard ? $dto->due_day : null,
            'payment_account_id' => $isCard ? $dto->payment_account_id : null,
        ]);
    }

    public function update(Account $account, UpdateAccountData $dto): Account
    {
        return DB::transaction(function () use ($account, $dto) {
            if (! $account->isCreditCard()) {
                $account->update(['name' => $dto->name]);

                return $account;
            }

            $account->update([
                'name' => $dto->name,
                'credit_limit' => $dto->credit_limit,
                'closing_day' => $dto->closing_day,
                'due_day' => $dto->due_day,
                'payment_account_id' => $dto->payment_account_id,
            ]);

            if ($account->wasChanged(['closing_day', 'due_day'])) {
                $this->cards->reassignInvoices($account);
            }

            return $account;
        });
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
