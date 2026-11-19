<?php

namespace Tests\Feature;

use App\Interfaces\Services\IAccountService;
use App\Interfaces\Services\ICategoryService;
use App\Models\Account;
use App\Models\Category;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Inertia\Testing\AssertableInertia as Assert;
use Tests\TestCase;

/**
 * Lista de transações: um mês por vez, resumo, busca e filtros por tipo de lançamento.
 */
class TransactionListTest extends TestCase
{
    use RefreshDatabase;

    private User $user;

    private Account $account;

    protected function setUp(): void
    {
        parent::setUp();

        $this->travelTo('2026-11-18 10:00:00');

        $this->user = User::factory()->create();
        app(IAccountService::class)->createDefaultForUser($this->user->id);
        app(ICategoryService::class)->createDefaultsForUser($this->user->id);
        $this->account = Account::create(['user_id' => $this->user->id, 'name' => 'Bradesco', 'type' => 'checking', 'balance' => 0]);

        $expense = Category::where('user_id', $this->user->id)->where('name', 'Transporte')->value('id');
        $income = Category::where('user_id', $this->user->id)->where('name', 'Salário')->value('id');

        $base = [
            'account_id' => $this->account->id,
            'is_installment' => false,
            'installments_count' => 2,
            'installment_start' => 1,
            'amount_mode' => 'installment',
            'is_recurring' => false,
            'frequency' => 'monthly',
        ];

        foreach ([
            ['description' => 'Salário', 'amount' => 3800, 'type' => 'income', 'category_id' => $income, 'date' => '2026-11-05'],
            ['description' => 'Uber ida', 'amount' => 111.25, 'type' => 'expense', 'category_id' => $expense, 'date' => '2026-11-10'],
            ['description' => 'Conta de luz', 'amount' => 200, 'type' => 'expense', 'category_id' => $expense, 'date' => '2026-11-30'],
            ['description' => 'Caixa Empréstimo', 'amount' => 179.08, 'type' => 'expense', 'category_id' => $expense, 'date' => '2026-11-20', 'is_installment' => true, 'installments_count' => 3],
        ] as $payload) {
            $this->actingAs($this->user)
                ->post(route('transactions.store'), [...$base, ...$payload])
                ->assertSessionHasNoErrors();
        }
    }

    public function test_defaults_to_the_current_month_with_summary(): void
    {
        $this->actingAs($this->user)
            ->get(route('transactions.index'))
            ->assertInertia(fn (Assert $page) => $page
                ->where('filters.month', '2026-11')
                // Salário, Uber, luz (dia 30, último do mês) e só a 1ª parcela do empréstimo.
                ->has('transactions.data', 4)
                ->where('summary.income', fn ($v) => (float) $v === 3800.0)
                ->where('summary.expense', fn ($v) => (float) $v === 490.33)
                ->where('summary.balance', fn ($v) => (float) $v === 3309.67)
                // A vencer: luz (30/11) e a parcela (20/11), ambas depois de hoje (18/11).
                ->where('summary.due', fn ($v) => (float) $v === 379.08)
                ->where('summary.due_count', 2));
    }

    public function test_navigates_months_and_all_period(): void
    {
        $this->actingAs($this->user)
            ->get(route('transactions.index', ['month' => '2026-12']))
            ->assertInertia(fn (Assert $page) => $page->has('transactions.data', 1));

        $this->actingAs($this->user)
            ->get(route('transactions.index', ['all' => 1]))
            ->assertInertia(fn (Assert $page) => $page
                ->has('transactions.data', 6)
                ->where('summary', null)
                ->where('filters.all', '1'));
    }

    public function test_search_and_kind_filters(): void
    {
        $this->actingAs($this->user)
            ->get(route('transactions.index', ['search' => 'UBER']))
            ->assertInertia(fn (Assert $page) => $page
                ->has('transactions.data', 1)
                ->where('transactions.data.0.name', 'Uber ida'));

        $this->actingAs($this->user)
            ->get(route('transactions.index', ['all' => 1, 'kind' => 'installment']))
            ->assertInertia(fn (Assert $page) => $page->has('transactions.data', 3));
    }
}
