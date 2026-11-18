<?php

namespace Tests\Feature;

use App\Interfaces\Services\IAccountService;
use App\Interfaces\Services\ICategoryService;
use App\Models\Account;
use App\Models\Category;
use App\Models\Installment;
use App\Models\Transaction;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class TransactionManageTest extends TestCase
{
    use RefreshDatabase;

    private User $user;

    private Account $account;

    private Category $expenseCategory;

    private Category $incomeCategory;

    protected function setUp(): void
    {
        parent::setUp();

        $this->user = User::factory()->create();
        $this->account = app(IAccountService::class)->createDefaultForUser($this->user->id);
        app(ICategoryService::class)->createDefaultsForUser($this->user->id);
        $this->expenseCategory = Category::where('user_id', $this->user->id)->where('name', 'Alimentação')->firstOrFail();
        $this->incomeCategory = Category::where('user_id', $this->user->id)->where('name', 'Salário')->firstOrFail();
    }

    /**
     * @param  array<string, mixed>  $overrides
     */
    private function createTransaction(array $overrides = []): Transaction
    {
        $this->actingAs($this->user)
            ->post(route('transactions.store'), [
                'description' => 'Mercado',
                'amount' => 100,
                'type' => 'expense',
                'category_id' => $this->expenseCategory->id,
                'account_id' => $this->account->id,
                'date' => now()->toDateString(),
                'is_installment' => false,
                'installments_count' => 2,
                'is_recurring' => false,
                'frequency' => 'monthly',
                ...$overrides,
            ])
            ->assertSessionHasNoErrors();

        return Transaction::orderBy('installment_number')->firstOrFail();
    }

    public function test_update_adjusts_balance(): void
    {
        $transaction = $this->createTransaction();
        $this->assertEquals(-100.0, (float) $this->account->fresh()->balance);

        $this->actingAs($this->user)
            ->put(route('transactions.update', $transaction), [
                'description' => 'Salário',
                'amount' => 250,
                'type' => 'income',
                'category_id' => $this->incomeCategory->id,
                'account_id' => $this->account->id,
                'date' => now()->toDateString(),
            ])
            ->assertSessionHasNoErrors()
            ->assertRedirect();

        $this->assertEquals(250.0, (float) $this->account->fresh()->balance);
        $this->assertDatabaseHas('transactions', ['id' => $transaction->id, 'name' => 'Salário', 'type' => 'income']);
    }

    public function test_update_can_move_transaction_to_another_account(): void
    {
        $transaction = $this->createTransaction();
        $other = Account::create(['user_id' => $this->user->id, 'name' => 'Nubank', 'type' => 'checking', 'balance' => 0]);

        $this->actingAs($this->user)
            ->put(route('transactions.update', $transaction), [
                'description' => 'Mercado',
                'amount' => 100,
                'type' => 'expense',
                'category_id' => $this->expenseCategory->id,
                'account_id' => $other->id,
                'date' => now()->toDateString(),
            ])
            ->assertSessionHasNoErrors();

        $this->assertEquals(0.0, (float) $this->account->fresh()->balance);
        $this->assertEquals(-100.0, (float) $other->fresh()->balance);
    }

    public function test_delete_reverts_balance(): void
    {
        $transaction = $this->createTransaction();

        $this->actingAs($this->user)
            ->delete(route('transactions.destroy', $transaction))
            ->assertRedirect();

        $this->assertSame(0, Transaction::count());
        $this->assertEquals(0.0, (float) $this->account->fresh()->balance);
    }

    public function test_deleting_a_parcel_deletes_the_whole_installment(): void
    {
        $this->createTransaction(['amount' => 300, 'is_installment' => true, 'installments_count' => 3]);
        $second = Transaction::where('installment_number', 2)->firstOrFail();

        $this->actingAs($this->user)
            ->delete(route('transactions.destroy', $second))
            ->assertRedirect();

        $this->assertSame(0, Transaction::count());
        $this->assertSame(0, Installment::count());
        $this->assertEquals(0.0, (float) $this->account->fresh()->balance);
    }

    public function test_editing_a_parcel_keeps_its_suffix(): void
    {
        $this->createTransaction(['amount' => 300, 'is_installment' => true, 'installments_count' => 3]);
        $second = Transaction::where('installment_number', 2)->firstOrFail();

        $this->actingAs($this->user)
            ->put(route('transactions.update', $second), [
                'description' => 'Geladeira',
                'amount' => 120,
                'type' => 'expense',
                'category_id' => $this->expenseCategory->id,
                'account_id' => $this->account->id,
                'date' => $second->date->toDateString(),
            ])
            ->assertSessionHasNoErrors();

        $this->assertSame('Geladeira (2/3)', $second->fresh()->name);
        // A 2ª parcela não entra no saldo, então editar não muda o saldo.
        $this->assertEquals(-100.0, (float) $this->account->fresh()->balance);
    }

    public function test_cannot_touch_another_users_transaction(): void
    {
        $transaction = $this->createTransaction();
        $intruder = User::factory()->create();

        $this->actingAs($intruder)
            ->delete(route('transactions.destroy', $transaction))
            ->assertNotFound();

        $this->assertSame(1, Transaction::count());
    }

    public function test_recent_includes_future_dated_transactions(): void
    {
        $this->createTransaction([
            'description' => 'Salário',
            'type' => 'income',
            'category_id' => $this->incomeCategory->id,
            'date' => now()->addMonth()->toDateString(),
        ]);

        $this->actingAs($this->user)
            ->get(route('dashboard'))
            ->assertInertia(fn ($page) => $page
                ->has('recentTransactions', 1)
                ->where('recentTransactions.0.name', 'Salário'));
    }
}
