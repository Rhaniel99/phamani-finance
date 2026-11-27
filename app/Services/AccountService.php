<?php

namespace App\Services;

use App\DTOs\Account\StoreAccountData;
use App\DTOs\Account\UpdateAccountData;
use App\Interfaces\Repositories\IAccountRepository;
use App\Interfaces\Services\IAccountService;
use App\Interfaces\Services\ICreditCardService;
use App\Interfaces\Services\IInstallmentService;
use App\Interfaces\Services\ITransactionService;
use App\Models\Account;
use App\Models\Installment;
use App\Models\RecurringTransaction;
use App\Models\Transaction;
use Illuminate\Validation\ValidationException;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Support\Facades\DB;

class AccountService implements IAccountService
{
    public function __construct(
        protected IAccountRepository $repository,
        protected ICreditCardService $cards,
        protected ITransactionService $transactions,
        protected IInstallmentService $installments,
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

    public function deletionImpact(Account $account): array
    {
        $transactions = Transaction::query()->where('account_id', $account->id)->whereNull('mirrored_from_id');

        return [
            'transactions' => (clone $transactions)->count(),
            'installments' => (clone $transactions)->whereNotNull('installment_id')->distinct()->count('installment_id'),
            'recurring' => RecurringTransaction::query()->where('account_id', $account->id)->count(),
            'invoices' => $account->invoices()->count(),
            'paid_invoices' => $account->invoices()->whereNotNull('paid_at')->count(),
            // Divididas com contatos que têm conta no Phamani: a cópia deles também some.
            'shared' => (clone $transactions)->whereHas('splits', fn ($q) => $q->whereNotNull('contact_id'))->count(),
            // Cópias de compras de outras pessoas (divisões aceitas): ficam, só que sem conta.
            'mirrors' => Transaction::query()->where('account_id', $account->id)->whereNotNull('mirrored_from_id')->count(),
            'balance' => (float) $account->balance,
            'is_last' => $this->isLastRegularAccount($account),
        ];
    }

    public function delete(Account $account): void
    {
        if ($this->isLastRegularAccount($account)) {
            throw ValidationException::withMessages([
                'account' => 'Esta é sua única conta (fora os cartões). Crie outra antes de excluir.',
            ]);
        }

        DB::transaction(function () use ($account) {
            // Cópias de compras de outras pessoas: não são suas, continuam (sem conta).
            Transaction::query()
                ->where('account_id', $account->id)
                ->whereNotNull('mirrored_from_id')
                ->update(['account_id' => null, 'balance_applied' => false]);

            // Parcelamentos inteiros (todas as parcelas são do mesmo cartão/conta).
            $installmentIds = Transaction::query()
                ->where('account_id', $account->id)
                ->whereNotNull('installment_id')
                ->distinct()
                ->pluck('installment_id');

            // Um por vez, buscando de novo (modelo avulso: os serviços carregam relações sob demanda).
            foreach ($installmentIds as $id) {
                $installment = Installment::query()->find($id);
                if ($installment !== null) {
                    $this->installments->deleteInstallment($installment);
                }
            }

            // Demais transações uma a uma: desfaz divisões, cópias e reembolsos como na exclusão normal.
            $ids = Transaction::query()->where('account_id', $account->id)->orderBy('date')->pluck('id');
            foreach ($ids as $id) {
                $transaction = Transaction::query()->find($id);
                if ($transaction !== null) {
                    $this->transactions->delete($transaction);
                }
            }

            // Recorrências param (as ocorrências já foram excluídas acima).
            RecurringTransaction::query()->where('account_id', $account->id)->delete();

            // Faturas, importações de extrato: saem em cascata. Cartões que pagavam por esta
            // conta ficam sem conta padrão; faturas pagas por ela continuam pagas.
            $account->delete();
        });
    }

    /**
     * Última conta que não é cartão: sem ela não há de onde sair/entrar dinheiro.
     */
    private function isLastRegularAccount(Account $account): bool
    {
        if ($account->isCreditCard()) {
            return false;
        }

        return ! $this->repository->query()
            ->where('user_id', $account->user_id)
            ->whereKeyNot($account->id)
            ->where('type', '!=', 'credit')
            ->exists();
    }
}
