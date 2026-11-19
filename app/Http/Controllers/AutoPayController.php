<?php

namespace App\Http\Controllers;

use App\Interfaces\Services\IPaymentService;
use App\Models\Installment;
use App\Models\RecurringTransaction;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Inertia\Inertia;

/**
 * Liga/desliga o débito automático de uma série existente (recorrência ou parcelamento).
 * Ao ligar, o que já venceu e está em aberto é marcado como pago na data do vencimento.
 */
class AutoPayController extends Controller
{
    public function __construct(
        protected IPaymentService $payments,
    ) {}

    public function recurring(Request $request, RecurringTransaction $recurring): RedirectResponse
    {
        return $this->toggle($request, $recurring);
    }

    public function installment(Request $request, Installment $installment): RedirectResponse
    {
        return $this->toggle($request, $installment);
    }

    private function toggle(Request $request, Model $series): RedirectResponse
    {
        abort_unless($series->getAttribute('user_id') === (string) $request->user()?->getAuthIdentifier(), 404);

        $enabled = $request->boolean('enabled');
        $series->forceFill(['auto_pay' => $enabled])->save();

        if ($enabled) {
            $this->payments->processAutoPay();
        }

        Inertia::flash('toast', [
            'type' => 'success',
            'message' => $enabled ? 'Débito automático ligado.' : 'Débito automático desligado.',
        ]);

        return back();
    }
}
