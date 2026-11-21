#!/usr/bin/env bash
# Phamani — corrige: ao editar a data de uma transação paga para o futuro, ela continuava "paga"
# e o valor seguia descontado do saldo. Agora, ao mudar a data, o status volta à regra de criação
# (futura → pendente e sai do saldo; hoje/passada → paga na nova data; cartão → sempre paga).
# Sem mudança de data, o status não é tocado.
# Uso: na raiz do projeto ->  bash fix-status-ao-mudar-data.sh
set -euo pipefail
[ -f artisan ] && [ -f app/Services/TransactionService.php ] || { echo "Rode na raiz do projeto Phamani."; exit 1; }
BACKUP=".backup-$(date +%Y%m%d%H%M%S)"
backup() { if [ -f "$1" ]; then mkdir -p "$BACKUP/$(dirname "$1")"; cp "$1" "$BACKUP/$1"; fi; }
write() { backup "$1"; mkdir -p "$(dirname "$1")"; cat > "$1"; echo "  ok  $1"; }
echo "Aplicando arquivos (backup em $BACKUP/):"

write 'app/Services/TransactionService.php' <<'PHAMANI_EOF'
<?php

namespace App\Services;

use App\DTOs\Transaction\StoreTransactionData;
use App\DTOs\Transaction\UpdateTransactionData;
use App\Interfaces\Repositories\ITransactionRepository;
use App\Interfaces\Services\IBalanceService;
use App\Interfaces\Services\IInstallmentService;
use App\Interfaces\Services\IRecurringTransactionService;
use App\Interfaces\Services\IShareService;
use App\Interfaces\Services\ISplitService;
use App\Interfaces\Services\ITransactionService;
use App\Models\Account;
use App\Models\Transaction;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Carbon;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;

class TransactionService implements ITransactionService
{
    public function __construct(
        protected ITransactionRepository $repository,
        protected IBalanceService $balance,
        protected IInstallmentService $installmentService,
        protected IRecurringTransactionService $recurringService,
        protected ISplitService $splits,
        protected IShareService $shares,
    ) {}

    public function create(string $userId, StoreTransactionData $dto): Model
    {
        $this->splits->validate($dto->split, $dto->amount, $dto->type);

        if ($dto->is_installment) {
            return $this->installmentService->createInstallment($userId, $dto);
        }

        if ($dto->is_recurring) {
            return $this->recurringService->createRecurringTransaction($userId, $dto);
        }

        return DB::transaction(function () use ($userId, $dto) {
            $parts = $this->splits->compute($dto->amount, $dto->split);

            /** @var Transaction $transaction */
            $transaction = $this->repository->create([
                'user_id' => $userId,
                // Se outra pessoa pagou, nenhuma conta sua é afetada.
                'account_id' => $parts['paid_by_contact_id'] === null ? $dto->account_id : null,
                'category_id' => $dto->category_id,
                'name' => $dto->description,
                'description' => $dto->description,
                'type' => $dto->type,
                'amount' => $parts['amount'],
                'total_amount' => $parts['total_amount'],
                'paid_by_contact_id' => $parts['paid_by_contact_id'],
                'date' => $dto->date,
            ]);

            $this->splits->sync($transaction, $parts['shares']);

            // Data futura: fica "agendada" e só entra no saldo quando a data chegar.
            $this->balance->applyIfDue($transaction);

            return $transaction;
        });
    }

    public function update(Transaction $transaction, UpdateTransactionData $dto): Transaction
    {
        $this->splits->validate($dto->split, $dto->amount, $dto->type);

        return DB::transaction(function () use ($transaction, $dto) {
            // Tira o efeito antigo (se havia) e reaplica com os dados novos, se a data já chegou.
            // Cobre troca de valor, de tipo, de conta e de data.
            $this->balance->revert($transaction);

            // Parcelas mantêm o sufixo "(n/total)" no nome.
            $name = $dto->description;
            if ($transaction->installment_id !== null && $transaction->installment !== null) {
                $name = "{$dto->description} ({$transaction->installment_number}/{$transaction->installment->installments})";
            }

            $parts = $this->splits->compute($dto->amount, $dto->split);
            $accountId = $parts['paid_by_contact_id'] === null ? $dto->account_id : null;

            $this->repository->update($transaction->id, [
                'account_id' => $accountId,
                'category_id' => $dto->category_id,
                'name' => $name,
                'description' => $dto->description,
                'type' => $dto->type,
                'amount' => $parts['amount'],
                'total_amount' => $parts['total_amount'],
                'paid_by_contact_id' => $parts['paid_by_contact_id'],
                'date' => $dto->date,
                'paid_at' => $this->paidAtAfterEdit($transaction, $dto->date, $accountId),
            ]);

            $transaction->refresh();
            $this->splits->sync($transaction, $parts['shares']);
            $this->balance->applyIfDue($transaction);

            if ($dto->apply_to_following && $transaction->installment_id !== null) {
                $this->installmentService->updateFollowingParcels($transaction, $dto->amount, $dto->split);
            }

            return $transaction;
        });
    }

    /**
     * Ao mudar a data, o status volta à regra de criação:
     * data futura → pendente (não mexe no saldo); hoje/passada → paga na nova data; cartão → sempre paga.
     * Sem mudança de data, o status fica como está.
     */
    private function paidAtAfterEdit(Transaction $transaction, string $newDate, ?string $accountId): ?string
    {
        $newDate = Carbon::parse($newDate)->toDateString();
        $current = $transaction->paid_at?->toDateString();

        if ($transaction->date->toDateString() === $newDate) {
            return $current;
        }

        $isCard = $accountId !== null && Account::query()->whereKey($accountId)->value('type') === 'credit';

        return $isCard || $newDate <= now()->toDateString() ? $newDate : null;
    }

    public function delete(Transaction $transaction): void
    {
        if ($transaction->installment_id !== null && $transaction->installment !== null) {
            $this->installmentService->deleteInstallment($transaction->installment);

            return;
        }

        DB::transaction(function () use ($transaction) {
            // Quem aceitou a divisão perde a cópia.
            $this->shares->removeFor($transaction);
            $this->balance->revert($transaction);
            $this->repository->delete($transaction->id);
        });
    }

    public function getRecentForDashboard(string $userId, int $limit = 5): Collection
    {
        return $this->repository->getLatestForUser($userId, $limit);
    }

    public function paginateForUser(string $userId, array $filters = [], int $perPage = 20): LengthAwarePaginator
    {
        return $this->repository->paginateForUser($userId, $filters, $perPage);
    }

    public function summaryForUser(string $userId, array $filters): array
    {
        return $this->repository->summaryForUser($userId, $filters);
    }
}
PHAMANI_EOF

write 'tests/Feature/PaymentStatusTest.php' <<'PHAMANI_EOF'
<?php

namespace Tests\Feature;

use App\Interfaces\Services\IAccountService;
use App\Interfaces\Services\ICategoryService;
use App\Models\Account;
use App\Models\Category;
use App\Models\Contact;
use App\Models\Share;
use App\Models\Transaction;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Inertia\Testing\AssertableInertia as Assert;
use Tests\TestCase;

/**
 * Status de pagamento: pago / pendente / atrasado, saldo só quando pago, débito automático
 * e "quem marca é quem pagou".
 */
class PaymentStatusTest extends TestCase
{
    use RefreshDatabase;

    private User $user;

    private Account $account;

    private Category $category;

    protected function setUp(): void
    {
        parent::setUp();

        $this->travelTo('2026-11-18 10:00:00');

        $this->user = User::factory()->create(['name' => 'Rhaniel']);
        app(IAccountService::class)->createDefaultForUser($this->user->id);
        app(ICategoryService::class)->createDefaultsForUser($this->user->id);
        $this->account = Account::create(['user_id' => $this->user->id, 'name' => 'Bradesco', 'type' => 'checking', 'balance' => 1000]);
        $this->category = Category::where('user_id', $this->user->id)->where('name', 'Outros')->firstOrFail();
    }

    /**
     * @param  array<string, mixed>  $overrides
     */
    private function store(array $overrides = [], ?User $as = null): void
    {
        $this->actingAs($as ?? $this->user)
            ->post(route('transactions.store'), [
                'description' => 'Boleto',
                'amount' => 100,
                'type' => 'expense',
                'category_id' => $this->category->id,
                'account_id' => $this->account->id,
                'date' => '2026-11-18',
                'is_installment' => false,
                'installments_count' => 2,
                'installment_start' => 1,
                'amount_mode' => 'installment',
                'is_recurring' => false,
                'frequency' => 'monthly',
                ...$overrides,
            ])
            ->assertSessionHasNoErrors();
    }

    private function balance(): float
    {
        return (float) $this->account->fresh()->balance;
    }

    public function test_initial_status_follows_the_date_and_cards_are_always_paid(): void
    {
        $this->store(['description' => 'Hoje']);
        $this->store(['description' => 'Futuro', 'date' => '2026-12-10']);

        $card = Account::create([
            'user_id' => $this->user->id, 'name' => 'Nubank', 'type' => 'credit', 'balance' => 0,
            'credit_limit' => 1000, 'closing_day' => 25, 'due_day' => 5,
        ]);
        $this->store(['description' => 'Cartão', 'account_id' => $card->id, 'date' => '2026-12-10']);

        $this->assertSame('2026-11-18', Transaction::where('name', 'Hoje')->firstOrFail()->paid_at->toDateString());
        $this->assertNull(Transaction::where('name', 'Futuro')->firstOrFail()->paid_at);
        $this->assertNotNull(Transaction::where('name', 'Cartão')->firstOrFail()->paid_at);
        $this->assertEquals(900.0, $this->balance()); // só "Hoje"
    }

    public function test_overdue_does_not_touch_balance_until_marked_paid(): void
    {
        $this->store(['date' => '2026-11-20']);
        $t = Transaction::firstOrFail();

        $this->travelTo('2026-11-25 10:00:00');
        $this->artisan('phamani:process-due')->assertSuccessful();

        $this->assertNull($t->fresh()->paid_at);
        $this->assertEquals(1000.0, $this->balance());

        $this->actingAs($this->user)
            ->get(route('dashboard'))
            ->assertInertia(fn (Assert $page) => $page->where('kpis.overdue.count', 1));

        $this->actingAs($this->user)
            ->get(route('transactions.index', ['status' => 'overdue']))
            ->assertInertia(fn (Assert $page) => $page
                ->has('transactions.data', 1)
                ->where('summary.overdue_count', 1));

        $this->actingAs($this->user)->post(route('transactions.pay', $t))->assertRedirect();
        $this->assertSame('2026-11-25', $t->fresh()->paid_at->toDateString());
        $this->assertEquals(900.0, $this->balance());

        $this->actingAs($this->user)->delete(route('transactions.unpay', $t))->assertRedirect();
        $this->assertNull($t->fresh()->paid_at);
        $this->assertEquals(1000.0, $this->balance());
    }

    public function test_recurring_without_auto_pay_waits_for_confirmation(): void
    {
        $this->store(['is_recurring' => true]);

        $this->travelTo('2026-12-18 10:00:00');
        $this->artisan('phamani:process-due')->assertSuccessful();

        $next = Transaction::orderByDesc('date')->firstOrFail();
        $this->assertSame('2026-12-18', $next->date->toDateString());
        $this->assertNull($next->paid_at);
        $this->assertEquals(900.0, $this->balance()); // só a 1ª (hoje)
    }

    public function test_auto_pay_marks_due_parcels_as_paid(): void
    {
        $this->store(['is_installment' => true, 'installments_count' => 3, 'auto_pay' => true]);

        $this->travelTo('2026-12-18 01:00:00');
        $this->artisan('phamani:process-due')->assertSuccessful();

        $parcels = Transaction::orderBy('installment_number')->get();
        $this->assertSame('2026-12-18', $parcels[1]->paid_at->toDateString());
        $this->assertNull($parcels[2]->paid_at);
        $this->assertEquals(800.0, $this->balance());
    }

    public function test_only_the_payer_marks_and_it_applies_to_everyone(): void
    {
        $mozi = User::factory()->create(['name' => 'Mozi']);
        app(IAccountService::class)->createDefaultForUser($mozi->id);
        app(ICategoryService::class)->createDefaultsForUser($mozi->id);
        $moziAccount = Account::create(['user_id' => $mozi->id, 'name' => 'Nubank', 'type' => 'checking', 'balance' => 1000]);

        $contact = Contact::create(['user_id' => $this->user->id, 'name' => 'Mozi', 'linked_user_id' => $mozi->id]);
        Contact::create(['user_id' => $mozi->id, 'name' => 'Rhaniel', 'linked_user_id' => $this->user->id]);

        // Boleto de amanhã, dividido, pago pela Mozi.
        $this->store([
            'date' => '2026-11-19',
            'account_id' => null,
            'split' => [
                'mode' => 'equal',
                'participants' => [['contact_id' => null], ['contact_id' => $contact->id]],
                'paid_by_contact_id' => $contact->id,
            ],
        ]);
        $source = Transaction::where('user_id', $this->user->id)->firstOrFail();

        $this->actingAs($mozi)
            ->post(route('shares.accept', Share::firstOrFail()), [
                'category_id' => Category::where('user_id', $mozi->id)->where('name', 'Outros')->value('id'),
                'account_id' => $moziAccount->id,
            ])
            ->assertSessionHasNoErrors();
        $mirror = Transaction::where('user_id', $mozi->id)->firstOrFail();

        // Eu não pago esse boleto: não posso marcar.
        $this->actingAs($this->user)
            ->post(route('transactions.pay', $source))
            ->assertSessionHasErrors('paid');
        $this->assertNull($source->fresh()->paid_at);

        // Ela marca na cópia dela: vale para as duas, e o total sai da conta dela.
        $this->actingAs($mozi)->post(route('transactions.pay', $mirror))->assertSessionHasNoErrors();

        $this->assertNotNull($source->fresh()->paid_at);
        $this->assertNotNull($mirror->fresh()->paid_at);
        $this->assertEquals(900.0, (float) $moziAccount->fresh()->balance);
        $this->assertEquals(1000.0, $this->balance());
    }

    public function test_turning_on_auto_pay_settles_overdue_parcels(): void
    {
        $this->store(['is_installment' => true, 'installments_count' => 3]);
        $installment = \App\Models\Installment::firstOrFail();

        $this->travelTo('2026-12-20 10:00:00');
        $this->artisan('phamani:process-due')->assertSuccessful();
        $this->assertEquals(900.0, $this->balance()); // 2ª parcela atrasada

        $this->actingAs($this->user)
            ->post(route('installments.auto-pay', $installment), ['enabled' => true])
            ->assertRedirect();

        $this->assertTrue($installment->fresh()->auto_pay);
        $this->assertSame('2026-12-18', Transaction::where('installment_number', 2)->firstOrFail()->paid_at->toDateString());
        $this->assertEquals(800.0, $this->balance());

        $this->actingAs(User::factory()->create())
            ->post(route('installments.auto-pay', $installment), ['enabled' => false])
            ->assertNotFound();
    }

    public function test_moving_a_paid_transaction_to_the_future_makes_it_pending_and_restores_the_balance(): void
    {
        $this->store(['description' => 'Telefone', 'amount' => 625]);
        $transaction = Transaction::where('description', 'Telefone')->firstOrFail();

        $this->assertNotNull($transaction->paid_at);
        $this->assertEqualsWithDelta(375.0, $this->balance(), 0.001);

        $this->actingAs($this->user)
            ->put(route('transactions.update', $transaction), [
                'description' => 'Telefone',
                'amount' => 625,
                'type' => 'expense',
                'category_id' => $this->category->id,
                'account_id' => $this->account->id,
                'date' => '2026-12-04',
            ])
            ->assertSessionHasNoErrors();

        $transaction->refresh();
        $this->assertNull($transaction->paid_at);
        $this->assertFalse((bool) $transaction->balance_applied);
        $this->assertEqualsWithDelta(1000.0, $this->balance(), 0.001);
    }

    public function test_editing_without_changing_the_date_keeps_the_status(): void
    {
        $this->store(['description' => 'Futuro', 'date' => '2026-12-10']);
        $transaction = Transaction::where('description', 'Futuro')->firstOrFail();

        $this->actingAs($this->user)->post(route('transactions.pay', $transaction));
        $this->assertNotNull($transaction->fresh()->paid_at);

        $this->actingAs($this->user)
            ->put(route('transactions.update', $transaction), [
                'description' => 'Futuro (editado)',
                'amount' => 100,
                'type' => 'expense',
                'category_id' => $this->category->id,
                'account_id' => $this->account->id,
                'date' => '2026-12-10',
            ])
            ->assertSessionHasNoErrors();

        $this->assertNotNull($transaction->fresh()->paid_at);
        $this->assertEqualsWithDelta(900.0, $this->balance(), 0.001);
    }
}
PHAMANI_EOF

echo "Pronto. php artisan test --filter=PaymentStatus && commit + push."
