<?php

namespace Tests\Feature;

use App\Interfaces\Services\IAccountService;
use App\Interfaces\Services\ICategoryService;
use App\Interfaces\Services\IDashboardService;
use App\Models\Account;
use App\Models\Category;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Inertia\Testing\AssertableInertia as Assert;
use Tests\TestCase;

/**
 * Lista do mês "por pagamento": compra no cartão entra no mês em que a fatura vence.
 */
class PaymentViewTest extends TestCase
{
    use RefreshDatabase;

    private User $user;

    private Account $checking;

    private Account $card;

    private Category $category;

    protected function setUp(): void
    {
        parent::setUp();

        $this->travelTo('2026-11-18 10:00:00');

        $this->user = User::factory()->create();
        app(IAccountService::class)->createDefaultForUser($this->user->id);
        app(ICategoryService::class)->createDefaultsForUser($this->user->id);
        $this->category = Category::where('user_id', $this->user->id)->where('name', 'Outros')->firstOrFail();

        $this->checking = Account::create(['user_id' => $this->user->id, 'name' => 'Bradesco', 'type' => 'checking', 'balance' => 1000]);
        // Fecha dia 25, vence dia 5: compra de 18/11 cai na fatura de 05/12.
        $this->card = Account::create([
            'user_id' => $this->user->id, 'name' => 'Nubank', 'type' => 'credit', 'balance' => 0,
            'credit_limit' => 5000, 'closing_day' => 25, 'due_day' => 5,
        ]);

        $this->store('Jogos', 120, $this->card->id, '2026-11-18');
        $this->store('Energia', 300, $this->checking->id, '2026-12-07');
        $this->store('Mercado', 80, $this->checking->id, '2026-11-10');
    }

    private function store(string $name, float $amount, string $accountId, string $date): void
    {
        $this->actingAs($this->user)
            ->post(route('transactions.store'), [
                'description' => $name,
                'amount' => $amount,
                'type' => 'expense',
                'category_id' => $this->category->id,
                'account_id' => $accountId,
                'date' => $date,
                'is_installment' => false,
                'installments_count' => 2,
                'installment_start' => 1,
                'amount_mode' => 'installment',
                'is_recurring' => false,
                'frequency' => 'monthly',
            ])
            ->assertSessionHasNoErrors();
    }

    public function test_card_purchase_counts_in_the_invoice_month_by_default(): void
    {
        $this->actingAs($this->user)
            ->get(route('transactions.index', ['month' => '2026-12']))
            ->assertInertia(fn (Assert $page) => $page
                ->has('transactions.data', 2)
                ->where('summary.expense', fn ($v) => (float) $v === 420.0)
                // Fatura não paga, vence 05/12: entra em "a vencer".
                ->where('summary.due', fn ($v) => (float) $v === 420.0));

        $this->actingAs($this->user)
            ->get(route('transactions.index', ['month' => '2026-11']))
            ->assertInertia(fn (Assert $page) => $page
                ->has('transactions.data', 1)
                ->where('summary.expense', fn ($v) => (float) $v === 80.0));
    }

    public function test_purchase_view_keeps_the_purchase_date(): void
    {
        $this->actingAs($this->user)
            ->get(route('transactions.index', ['month' => '2026-11', 'view' => 'purchase']))
            ->assertInertia(fn (Assert $page) => $page
                ->has('transactions.data', 2)
                ->where('summary.expense', fn ($v) => (float) $v === 200.0));
    }

    public function test_dashboard_expense_and_cash_flow_follow_the_payment_month(): void
    {
        $dashboard = app(IDashboardService::class);

        // Novembro: só o mercado (o cartão vence em dezembro).
        $this->assertEquals(80.0, (float) $dashboard->kpis($this->user->id)['expense']['value']);

        $flow = collect($dashboard->cashFlow($this->user->id, 'yearly'));
        $this->assertEquals(80.0, $flow[10]['expense']);
        $this->assertEquals(420.0, $flow[11]['expense']);

        // Categorias continuam pela data da compra (novembro: mercado + jogos).
        $this->assertEquals(200.0, collect($dashboard->categoryPie($this->user->id, 'monthly'))->sum('value'));
    }
}
