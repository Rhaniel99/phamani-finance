<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Status de pagamento.
 *
 * - transactions.paid_at: quando foi pago/recebido. Status: pago (paid_at), pendente (sem paid_at e
 *   data de hoje em diante) ou atrasado (sem paid_at e data no passado).
 *   O saldo da conta passa a mudar quando a transação é PAGA (não mais só pela data).
 * - auto_pay em recorrências e parcelamentos: "débito automático" — no dia, já marca como pago.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('transactions', function (Blueprint $table) {
            $table->date('paid_at')->nullable();
        });

        Schema::table('recurring_transactions', function (Blueprint $table) {
            $table->boolean('auto_pay')->default(false);
        });

        Schema::table('installments', function (Blueprint $table) {
            $table->boolean('auto_pay')->default(false);
        });

        $today = now()->toDateString();
        $cards = DB::table('accounts')->where('type', 'credit')->pluck('id');

        // O que já entrou no saldo, ou já tem data no passado, conta como pago na própria data.
        DB::table('transactions')
            ->where(fn ($q) => $q->where('balance_applied', true)->orWhere('date', '<=', $today))
            ->update(['paid_at' => DB::raw('date')]);

        // Compras no cartão contam sempre como pagas: a dívida está na fatura.
        DB::table('transactions')->whereIn('account_id', $cards)->update(['paid_at' => DB::raw('date')]);
    }

    public function down(): void
    {
        Schema::table('installments', fn (Blueprint $table) => $table->dropColumn('auto_pay'));
        Schema::table('recurring_transactions', fn (Blueprint $table) => $table->dropColumn('auto_pay'));
        Schema::table('transactions', fn (Blueprint $table) => $table->dropColumn('paid_at'));
    }
};
